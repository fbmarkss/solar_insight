// Caminho: lib/utils/calculadora_energetica.dart
// Descrição: Motor de cálculo energético (Com Lógica de Inversor vs Painéis, Custo de Disponibilidade e Conciliação de Saldo).

import 'package:hive/hive.dart';
import '../models/usina.dart';
import '../models/lancamento.dart';

// --- CLASSES DE DADOS (Contêineres de Resultados) ---

class MetricasGerais {
  final double totalGeradoKwh;
  final double totalInjetadoKwh;
  final double totalAutoconsumoKwh;
  final double valorTotalEconomizadoR;
  final double percentualRoi;
  final double mediaGeracao3Meses;
  final double mediaConsumo3Meses;
  final double saldoCreditosEstimado;

  MetricasGerais({
    required this.totalGeradoKwh,
    required this.totalInjetadoKwh,
    required this.totalAutoconsumoKwh,
    required this.valorTotalEconomizadoR,
    required this.percentualRoi,
    required this.mediaGeracao3Meses,
    required this.mediaConsumo3Meses,
    required this.saldoCreditosEstimado,
  });
}

class BalancoItem {
  final String nome;
  final String tipo;
  final double percentual;
  final double creditoRecebido;
  final double consumoReal;
  final double saldo;

  BalancoItem({
    required this.nome,
    required this.tipo,
    required this.percentual,
    required this.creditoRecebido,
    required this.consumoReal,
    required this.saldo,
  });
}

class RelatorioMensal {
  final double geracaoTotal;
  final double injecaoTotal;
  final List<BalancoItem> itens;

  RelatorioMensal({
    required this.geracaoTotal,
    required this.injecaoTotal,
    required this.itens,
  });
}

class CalculadoraEnergetica {
  // ===========================================================================
  // MÉTODOS AUXILIARES
  // ===========================================================================

  /// Identifica a taxa de disponibilidade (Custo mínimo que NÃO pode ser abatido por créditos)
  static double _obterCustoDisponibilidade(Usina usina) {
    String t = usina.tipo.toLowerCase();
    if (t.contains('monof')) return 30.0;
    if (t.contains('bif')) return 50.0;
    // Padrão assumido como trifásico (100 kWh intocáveis)
    return 100.0;
  }

  // ===========================================================================
  // 0. CÁLCULO DE POTÊNCIA EFETIVA (Inversor vs Painéis)
  // ===========================================================================
  /// Calcula a potência real do sistema considerando o gargalo do Inversor.
  /// Se tiver muito painel para pouco inversor, limita pelo inversor (+30% de ganho de overload).
  static double calcularPotenciaEfetiva(Usina usina) {
    // 1. Potência dos Painéis (DC - O "Motor")
    double potenciaPaineisDc = usina.potenciaTotalPaineisKwp;

    // 2. Potência dos Inversores (AC - O "Gargalo")
    double potenciaInversoresAc = 0;
    if (usina.inversores.isNotEmpty) {
      potenciaInversoresAc = usina.inversores.fold(
        0.0,
        (sum, inv) => sum + (inv.potenciaKw * inv.quantidade),
      );
    }

    // Se não tiver inversor cadastrado, assume a dos painéis
    if (potenciaInversoresAc == 0) return potenciaPaineisDc;

    // 3. Lógica de Overloading (Fator de Dimensionamento)
    if (potenciaPaineisDc <= potenciaInversoresAc) {
      // Cenário Folgado: O inversor aguenta tudo. O limite são os painéis.
      return potenciaPaineisDc;
    } else {
      // Cenário Estrangulado (Clipping): Tem mais painel que inversor.
      // O sistema corta o pico, mas gera mais nas pontas do dia.
      // Regra: Consideramos o Inversor + 30% de ganho de eficiência (Overload eficiente).
      // Tudo acima de 1.3x o inversor é praticamente desperdício (perda por clipping).
      double limiteEficiente = potenciaInversoresAc * 1.30;

      return potenciaPaineisDc < limiteEficiente
          ? potenciaPaineisDc
          : limiteEficiente;
    }
  }

  // ===========================================================================
  // 1. CÁLCULO MACRO (DASHBOARD / VIDA ÚTIL)
  // ===========================================================================
  static MetricasGerais calcularMetricasGerais(
    Usina usina,
    List<LancamentoMensal> historico,
  ) {
    // Ordenação cronológica para o saldo acumulado (Rolling Balance) funcionar e calibrar
    historico.sort((a, b) => a.dataReferencia.compareTo(b.dataReferencia));

    double somaGeracao = 0;
    double somaInjetadaHistorico = 0;
    double somaEconomiaReais = 0;
    double saldoRollingKwh = 0;

    final boxUsinas = Hive.box<Usina>('usinas');
    final boxLancamentos = Hive.box<LancamentoMensal>('lancamentos');

    // Taxa Mínima que não pode ser abatida com créditos
    double custoDisponibilidade = _obterCustoDisponibilidade(usina);

    // Identifica as usinas mães (Se for beneficiária)
    List<Usina> geradorasMaes = [];
    if (!usina.isGeradora) {
      geradorasMaes = boxUsinas.values
          .where(
            (u) =>
                u.isGeradora &&
                u.beneficiarias.any((b) => b.idUsinaFilha == usina.id),
          )
          .toList();
    }

    for (var l in historico) {
      double entradaCreditoMes = 0;
      double consumoMes = l.energiaConsumidaRedeKwh;

      if (usina.isGeradora) {
        // --- CASO GERADORA ---
        somaGeracao += l.geracaoTotalKwh;
        entradaCreditoMes = l.energiaInjetadaKwh;

        double autoconsumo = (l.geracaoTotalKwh - l.energiaInjetadaKwh).clamp(
          0,
          double.infinity,
        );
        double consumoTotalReal = autoconsumo + l.energiaConsumidaRedeKwh;

        // Custo sem solar: (Consumo Total * Tarifa) + Custos Fixos/Demanda
        double custoSemSolar =
            (consumoTotalReal * l.tarifaKwh) + l.custoDemandaR;
        somaEconomiaReais += (custoSemSolar - l.valorFaturaR).clamp(
          0,
          double.infinity,
        );
      } else {
        // --- CASO BENEFICIÁRIA ---
        for (var mae in geradorasMaes) {
          try {
            var vinculo = mae.beneficiarias.firstWhere(
              (b) => b.idUsinaFilha == usina.id,
            );
            var lancMae = boxLancamentos.values.firstWhere(
              (lm) =>
                  lm.usinaId == mae.id &&
                  lm.dataReferencia.year == l.dataReferencia.year &&
                  lm.dataReferencia.month == l.dataReferencia.month &&
                  !lm.isDeletado,
            );
            entradaCreditoMes +=
                (lancMae.energiaInjetadaKwh * (vinculo.percentual / 100));
          } catch (_) {}
        }

        double custoSemSolar =
            (l.energiaConsumidaRedeKwh * l.tarifaKwh) + l.custoDemandaR;
        somaEconomiaReais += (custoSemSolar - l.valorFaturaR).clamp(
          0,
          double.infinity,
        );
      }

      somaInjetadaHistorico += entradaCreditoMes;

      // --- CÁLCULO: REGRA DO CUSTO DE DISPONIBILIDADE ---
      // Os créditos injetados SÓ PODEM abater o que ultrapassar a taxa mínima obrigatória.
      double consumoAbativel = consumoMes > custoDisponibilidade
          ? consumoMes - custoDisponibilidade
          : 0.0;

      // Saldo Acumulado Contábil
      saldoRollingKwh += (entradaCreditoMes - consumoAbativel);
      if (saldoRollingKwh < 0) saldoRollingKwh = 0;

      // --- NOVO: CONCILIAÇÃO BANCÁRIA DE SALDO ---
      // Se o usuário preencheu o campo de conciliação para este mês, o app abandona
      // o cálculo virtual e "sincroniza/sobrescreve" com a verdade da concessionária.
      if (l.saldoInformadoNaFatura != null) {
        saldoRollingKwh = l.saldoInformadoNaFatura!;
      }
    }

    // Médias (3 meses)
    double mediaGer = 0;
    double mediaCons = 0;
    if (historico.isNotEmpty) {
      var recentes = historico.length > 3
          ? historico.sublist(historico.length - 3)
          : historico;
      mediaGer =
          recentes.fold(0.0, (prev, e) => prev + e.geracaoTotalKwh) /
          recentes.length;
      mediaCons =
          recentes.fold(0.0, (prev, e) => prev + e.energiaConsumidaRedeKwh) /
          recentes.length;
    }

    return MetricasGerais(
      totalGeradoKwh: somaGeracao,
      totalInjetadoKwh: somaInjetadaHistorico,
      totalAutoconsumoKwh: (somaGeracao - somaInjetadaHistorico).clamp(
        0,
        double.infinity,
      ),
      valorTotalEconomizadoR: somaEconomiaReais,
      percentualRoi: usina.totalInvestido > 0
          ? (somaEconomiaReais / usina.totalInvestido) * 100
          : 0,
      mediaGeracao3Meses: mediaGer,
      mediaConsumo3Meses: mediaCons,
      saldoCreditosEstimado: saldoRollingKwh,
    );
  }

  // ===========================================================================
  // 2. CÁLCULO MENSAL (ABAS DE AUDITORIA / LISTA)
  // ===========================================================================
  static RelatorioMensal calcular(
    Usina geradora,
    LancamentoMensal lancamentoGeradora,
  ) {
    final boxLancamentos = Hive.box<LancamentoMensal>('lancamentos');
    final boxUsinas = Hive.box<Usina>('usinas');

    List<BalancoItem> relatorio = [];
    double injetadoTotal = lancamentoGeradora.energiaInjetadaKwh;

    for (var vinculo in geradora.beneficiarias) {
      double creditoDireito = injetadoTotal * (vinculo.percentual / 100);

      var lancamentoFilha = boxLancamentos.values.firstWhere(
        (l) =>
            l.usinaId == vinculo.idUsinaFilha &&
            l.dataReferencia.month == lancamentoGeradora.dataReferencia.month &&
            l.dataReferencia.year == lancamentoGeradora.dataReferencia.year &&
            !l.isDeletado,
        orElse: () => LancamentoMensal(
          usinaId: vinculo.idUsinaFilha,
          dataReferencia: lancamentoGeradora.dataReferencia,
          geracaoTotalKwh: 0,
          energiaInjetadaKwh: 0,
          energiaConsumidaRedeKwh: 0,
          tarifaKwh: 0,
          valorFaturaR: 0,
        ),
      );

      // Aplica a regra de disponibilidade também para as beneficiárias
      Usina? usinaFilha;
      try {
        usinaFilha = boxUsinas.values.firstWhere(
          (u) => u.id == vinculo.idUsinaFilha,
        );
      } catch (_) {}

      double custoDispFilha = usinaFilha != null
          ? _obterCustoDisponibilidade(usinaFilha)
          : 100.0;
      double consumoAbativelFilha =
          lancamentoFilha.energiaConsumidaRedeKwh > custoDispFilha
          ? lancamentoFilha.energiaConsumidaRedeKwh - custoDispFilha
          : 0.0;

      relatorio.add(
        BalancoItem(
          nome: vinculo.nome,
          tipo: 'BENEFICIARIA',
          percentual: vinculo.percentual,
          creditoRecebido: creditoDireito,
          consumoReal: lancamentoFilha.energiaConsumidaRedeKwh,
          saldo: creditoDireito - consumoAbativelFilha,
        ),
      );
    }

    double percGeradora =
        100 - geradora.beneficiarias.fold(0.0, (sum, b) => sum + b.percentual);
    if (percGeradora > 0) {
      double creditoGeradora = injetadoTotal * (percGeradora / 100);

      // Aplica a regra de disponibilidade para a usina geradora
      double custoDispGeradora = _obterCustoDisponibilidade(geradora);
      double consumoAbativelGeradora =
          lancamentoGeradora.energiaConsumidaRedeKwh > custoDispGeradora
          ? lancamentoGeradora.energiaConsumidaRedeKwh - custoDispGeradora
          : 0.0;

      relatorio.insert(
        0,
        BalancoItem(
          nome: "${geradora.nome} (Própria)",
          tipo: 'GERADORA',
          percentual: percGeradora,
          creditoRecebido: creditoGeradora,
          consumoReal: lancamentoGeradora.energiaConsumidaRedeKwh,
          saldo: creditoGeradora - consumoAbativelGeradora,
        ),
      );
    }

    return RelatorioMensal(
      geracaoTotal: lancamentoGeradora.geracaoTotalKwh,
      injecaoTotal: injetadoTotal,
      itens: relatorio,
    );
  }

  // ===========================================================================
  // 3. ALERTAS DE GESTÃO (ATUALIZADO COM NOME DA USINA)
  // ===========================================================================
  static List<Map<String, dynamic>> gerarAlertasDeGestao(
    Usina usina,
    LancamentoMensal? ultimo,
    double saldoCreditosGlobal,
  ) {
    List<Map<String, dynamic>> alertas = [];
    if (ultimo == null) return alertas;

    // A. ALERTA DE QUEDA DE PRODUÇÃO (Comparando com histórico recente)
    if (usina.isGeradora) {
      final boxLanc = Hive.box<LancamentoMensal>('lancamentos');
      final historico =
          boxLanc.values
              .where((l) => l.usinaId == usina.id && !l.isDeletado)
              .toList()
            ..sort((a, b) => b.dataReferencia.compareTo(a.dataReferencia));

      if (historico.length >= 2) {
        double geracaoAtual = ultimo.geracaoTotalKwh;
        var anteriores = historico.skip(1).take(3).toList();
        double mediaAnterior =
            anteriores.fold(0.0, (sum, l) => sum + l.geracaoTotalKwh) /
            anteriores.length;

        if (mediaAnterior > 0 && geracaoAtual < (mediaAnterior * 0.75)) {
          alertas.add({
            'tipo': 'queda_acentuada',
            'titulo': 'Queda em ${usina.nome}',
            'mensagem':
                'A geração caiu ${(100 - (geracaoAtual / mediaAnterior * 100)).toStringAsFixed(0)}% em relação à média recente.',
            'cor': 'orange',
            'icone': 'trending_down',
          });
        }
      }
    }

    // B. CÁLCULO DE CRÉDITO RECEBIDO
    double creditoRecebidoNoMes = 0;
    if (usina.isGeradora) {
      creditoRecebidoNoMes = ultimo.energiaInjetadaKwh;
    } else {
      final boxUsinas = Hive.box<Usina>('usinas');
      final boxLanc = Hive.box<LancamentoMensal>('lancamentos');
      final maes = boxUsinas.values.where(
        (u) =>
            u.isGeradora &&
            u.beneficiarias.any((b) => b.idUsinaFilha == usina.id),
      );

      for (var mae in maes) {
        try {
          final vinculo = mae.beneficiarias.firstWhere(
            (b) => b.idUsinaFilha == usina.id,
          );
          final lancMae = boxLanc.values.firstWhere(
            (lm) =>
                lm.usinaId == mae.id &&
                lm.dataReferencia.year == ultimo.dataReferencia.year &&
                lm.dataReferencia.month == ultimo.dataReferencia.month,
          );
          creditoRecebidoNoMes +=
              (lancMae.energiaInjetadaKwh * (vinculo.percentual / 100));
        } catch (_) {}
      }
    }

    // C. ALERTAS DE DEFICIT E RESERVA
    double consumo = ultimo.energiaConsumidaRedeKwh;
    double saldoMensal = creditoRecebidoNoMes - consumo;

    if (saldoMensal < 0) {
      double deficit = saldoMensal.abs();
      if (saldoCreditosGlobal > deficit) {
        alertas.add({
          'tipo': 'consumo_reserva',
          'titulo': 'Consumindo Reserva',
          'mensagem':
              'Na unidade ${usina.nome}, o consumo superou o recebido. Você usou ${deficit.toStringAsFixed(0)} kWh do saldo acumulado.',
          'cor': 'orange',
          'icone': 'hourglass_bottom',
        });
      } else {
        alertas.add({
          'tipo': 'deficit_real',
          'titulo': 'Gasto Superior ao Crédito',
          'mensagem':
              '${usina.nome} não teve crédito suficiente para cobrir o consumo. Fatura virá alta.',
          'cor': 'red',
          'icone': 'monetization_on',
        });
      }
    }

    return alertas;
  }

  // ===========================================================================
  // 4. SAÚDE E TENDÊNCIA
  // ===========================================================================
  static Map<String, dynamic> calcularSaudeSistema(
    Usina usina,
    List<LancamentoMensal> lancamentos,
  ) {
    if (!usina.isGeradora || lancamentos.isEmpty) {
      return {'eficiencia': 100.0, 'anos': 0.0};
    }

    // --- MUDANÇA: Usa a Potência Efetiva (Considerando Inversores) ---
    double potenciaEfetivaInstalada = calcularPotenciaEfetiva(usina);

    lancamentos.sort((a, b) => a.dataReferencia.compareTo(b.dataReferencia));
    double anosDeUso =
        DateTime.now().difference(lancamentos.first.dataReferencia).inDays /
        365.0;

    // Eficiência teórica baseada no tempo de uso
    double eficienciaEsperadaPeloTempo =
        (100.0 - (anosDeUso.clamp(0, double.infinity) * 0.5)).clamp(0, 100);

    return {
      'eficiencia': eficienciaEsperadaPeloTempo,
      'anos': anosDeUso.clamp(0, double.infinity),
      'potenciaNominal': potenciaEfetivaInstalada,
      'potenciaEfetiva':
          potenciaEfetivaInstalada * (eficienciaEsperadaPeloTempo / 100),
    };
  }

  // --- MUDANÇA: Estimativa baseada na Potência Efetiva (com Clipping) ---
  static double estimarProducaoIdealMensal(Usina usina) {
    // Fator médio Brasil: 120 kWh/mês por kWp instalado
    return calcularPotenciaEfetiva(usina) * 120.0;
  }
}
