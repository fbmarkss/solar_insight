// Caminho: lib/utils/calculadora_energetica.dart
// Descrição: Motor de cálculo energético (Com Inteligência Tarifária, TE/TUSD, Auditoria de Fio B, Alertas de Multa e Auditor de Desvio de Créditos).

import 'package:hive/hive.dart';
import '../models/usina.dart';
import '../models/lancamento.dart';

// --- CLASSES DE DADOS (Contêineres de Resultados) ---

class MetricasGerais {
  final double totalGeradoKwh;
  final double totalInjetadoKwh;
  final double totalAutoconsumoKwh;
  final double valorTotalEconomizadoR;
  // --- NOVOS CAMPOS AUDITORIA PRO ---
  final double custoFixoInevitavelR; // Demanda + Iluminação Pública
  final double totalMultasReativoR; // Dinheiro jogado no lixo
  final double totalCreditosDesviados; // O Placar do Prejuízo!
  // ----------------------------------
  final double percentualRoi;
  final double mediaGeracao3Meses;
  final double mediaConsumo3Meses;
  final double saldoCreditosEstimado;

  MetricasGerais({
    required this.totalGeradoKwh,
    required this.totalInjetadoKwh,
    required this.totalAutoconsumoKwh,
    required this.valorTotalEconomizadoR,
    required this.custoFixoInevitavelR,
    required this.totalMultasReativoR,
    required this.totalCreditosDesviados,
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

  static double _obterCustoDisponibilidade(Usina usina) {
    String t = usina.tipo.toLowerCase();
    if (t.contains('monof')) {
      return 30.0;
    }
    if (t.contains('bif')) {
      return 50.0;
    }
    return 100.0;
  }

  // --- HELPER CENTRALIZADO PARA EVITAR REPETIÇÃO DE CÓDIGO ---
  static double _calcularCreditoRecebidoLiquido(
    Usina usina,
    LancamentoMensal l,
  ) {
    if (usina.isGeradora) {
      double percentualEnviado = usina.beneficiarias.fold(
        0.0,
        (sum, b) => sum + b.percentual,
      );
      double energiaEnviada = l.energiaInjetadaKwh * (percentualEnviado / 100);
      return l.energiaInjetadaKwh - energiaEnviada;
    } else {
      double recebido = l.energiaInjetadaKwh;
      if (recebido == 0) {
        final boxUsinas = Hive.box<Usina>('usinas');
        final boxLancamentos = Hive.box<LancamentoMensal>('lancamentos');
        final maes = boxUsinas.values.where(
          (u) =>
              u.isGeradora &&
              u.beneficiarias.any((b) => b.idUsinaFilha == usina.id),
        );
        for (var mae in maes) {
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
            recebido +=
                (lancMae.energiaInjetadaKwh * (vinculo.percentual / 100));
          } catch (_) {}
        }
      }
      return recebido;
    }
  }

  // ===========================================================================
  // 0. CÁLCULO DE POTÊNCIA EFETIVA
  // ===========================================================================
  static double calcularPotenciaEfetiva(Usina usina) {
    double potenciaPaineisDc = usina.potenciaTotalPaineisKwp;
    double potenciaInversoresAc = 0;

    if (usina.inversores.isNotEmpty) {
      potenciaInversoresAc = usina.inversores.fold(
        0.0,
        (sum, inv) => sum + (inv.potenciaKw * inv.quantidade),
      );
    }

    if (potenciaInversoresAc == 0) {
      return potenciaPaineisDc;
    }

    if (potenciaPaineisDc <= potenciaInversoresAc) {
      return potenciaPaineisDc;
    } else {
      double limiteEficiente = potenciaInversoresAc * 1.30;
      return potenciaPaineisDc < limiteEficiente
          ? potenciaPaineisDc
          : limiteEficiente;
    }
  }

  // ===========================================================================
  // 1. CÁLCULO MACRO (DASHBOARD / VIDA ÚTIL) - COM INTELIGÊNCIA IA
  // ===========================================================================
  static MetricasGerais calcularMetricasGerais(
    Usina usina,
    List<LancamentoMensal> historico,
  ) {
    historico.sort((a, b) => a.dataReferencia.compareTo(b.dataReferencia));

    double somaGeracao = 0;
    double somaInjetadaHistorico = 0;
    double somaEconomiaReais = 0;
    double saldoRollingKwh = 0;

    // Novas somas financeiras
    double somaCustosFixos = 0;
    double somaMultas = 0;
    double somaDesviosConcessionaria = 0;

    double custoDisponibilidade = _obterCustoDisponibilidade(usina);

    for (var l in historico) {
      double entradaCreditoMesParaSaldo = _calcularCreditoRecebidoLiquido(
        usina,
        l,
      );
      double consumoMes = l.energiaConsumidaRedeKwh;

      // --- INTELIGÊNCIA TARIFÁRIA (O FIM DA TARIFA MÉDIA) ---
      double tarifaInteligente = l.tarifaKwh;

      if (l.grupoTarifario == 'A' ||
          l.modalidadeTarifaria == 'VERDE' ||
          l.modalidadeTarifaria == 'AZUL') {
        if ((l.tarifaTeForaPonta ?? 0) > 0) {
          tarifaInteligente =
              l.tarifaTeForaPonta! + (l.tarifaTusdForaPonta ?? 0);
        }
      } else {
        if ((l.tarifaTeUnica ?? 0) > 0) {
          tarifaInteligente = l.tarifaTeUnica! + (l.tarifaTusdUnica ?? 0);
        }
      }
      if (tarifaInteligente <= 0) {
        tarifaInteligente = l.tarifaKwh;
      }

      somaCustosFixos += l.custoDemandaR + (l.custoIluminacaoPublica ?? 0.0);
      somaMultas += (l.multaReativo ?? 0.0);

      if (usina.isGeradora) {
        somaGeracao += l.geracaoTotalKwh;
        somaInjetadaHistorico += l.energiaInjetadaKwh;

        double autoconsumo = (l.geracaoTotalKwh - l.energiaInjetadaKwh).clamp(
          0,
          double.infinity,
        );
        double consumoTotalReal = autoconsumo + l.energiaConsumidaRedeKwh;

        double custoSemSolar =
            (consumoTotalReal * tarifaInteligente) +
            l.custoDemandaR +
            (l.custoIluminacaoPublica ?? 0.0) +
            (l.multaReativo ?? 0.0);
        somaEconomiaReais += (custoSemSolar - l.valorFaturaR).clamp(
          0,
          double.infinity,
        );
      } else {
        somaInjetadaHistorico += entradaCreditoMesParaSaldo;

        double custoSemSolar =
            (l.energiaConsumidaRedeKwh * tarifaInteligente) +
            l.custoDemandaR +
            (l.custoIluminacaoPublica ?? 0.0) +
            (l.multaReativo ?? 0.0);
        somaEconomiaReais += (custoSemSolar - l.valorFaturaR).clamp(
          0,
          double.infinity,
        );
      }

      double consumoAbativel = consumoMes > custoDisponibilidade
          ? consumoMes - custoDisponibilidade
          : 0.0;

      saldoRollingKwh += (entradaCreditoMesParaSaldo - consumoAbativel);
      if (saldoRollingKwh < 0) {
        saldoRollingKwh = 0;
      }

      // --- A AUDITORIA HISTÓRICA DE DESVIO OCORRE AQUI ---
      if (l.saldoInformadoNaFatura != null) {
        double diferenca = saldoRollingKwh - l.saldoInformadoNaFatura!;
        if (diferenca > 5.0) {
          // Tolerância de arredondamento
          somaDesviosConcessionaria += diferenca;
        }
        // Após flagrar o erro, o app calibra com a "verdade" da conta para não propagar o erro
        saldoRollingKwh = l.saldoInformadoNaFatura!;
      }
    }

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
      custoFixoInevitavelR: somaCustosFixos,
      totalMultasReativoR: somaMultas,
      totalCreditosDesviados: somaDesviosConcessionaria,
      percentualRoi: usina.totalInvestido > 0
          ? (somaEconomiaReais / usina.totalInvestido) * 100
          : 0,
      mediaGeracao3Meses: mediaGer,
      mediaConsumo3Meses: mediaCons,
      saldoCreditosEstimado: saldoRollingKwh,
    );
  }

  // ===========================================================================
  // 1.5 O AUDITOR INDIVIDUAL DE MÊS A MÊS (Para colocar selos na UI)
  // ===========================================================================
  static double calcularDesvioDoMes(
    Usina usina,
    LancamentoMensal atual,
    LancamentoMensal? anterior,
  ) {
    if (atual.saldoInformadoNaFatura == null) {
      return 0.0;
    }
    if (anterior == null || anterior.saldoInformadoNaFatura == null) {
      return 0.0;
    }

    double recebido = _calcularCreditoRecebidoLiquido(usina, atual);
    double taxaMinima = _obterCustoDisponibilidade(usina);
    double consumoAbativel = atual.energiaConsumidaRedeKwh > taxaMinima
        ? atual.energiaConsumidaRedeKwh - taxaMinima
        : 0.0;

    double saldoMensalGerado = recebido - consumoAbativel;
    double saldoEsperado = anterior.saldoInformadoNaFatura! + saldoMensalGerado;

    if (saldoEsperado < 0) {
      saldoEsperado = 0;
    }

    double desvio = saldoEsperado - atual.saldoInformadoNaFatura!;
    return desvio > 5.0 ? desvio : 0.0;
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
  // 3. ALERTAS DE GESTÃO - EVOLUÇÃO PRO (Multas, Perdas e Auditoria de Saldo)
  // ===========================================================================
  static List<Map<String, dynamic>> gerarAlertasDeGestao(
    Usina usina,
    LancamentoMensal? ultimo,
    double saldoCreditosGlobal,
  ) {
    List<Map<String, dynamic>> alertas = [];
    if (ultimo == null) {
      return alertas;
    }

    // --- ALERTA PRO 1: MULTA DE ENERGIA REATIVA ---
    if ((ultimo.multaReativo ?? 0) > 0) {
      alertas.add({
        'tipo': 'fuga_dinheiro',
        'titulo': 'Fuga de Dinheiro (Multa)!',
        'mensagem':
            'A unidade ${usina.nome} pagou R\$ ${ultimo.multaReativo!.toStringAsFixed(2)} de multa por Energia Reativa (ERE/DRE). Peça a um eletricista para avaliar o Banco de Capacitores.',
        'cor': 'red',
        'icone': 'bolt',
      });
    }

    // --- ALERTA PRO 2: ALTO CUSTO DE DEMANDA / FIXO ---
    double custosFixos =
        ultimo.custoDemandaR + (ultimo.custoIluminacaoPublica ?? 0);
    if (ultimo.valorFaturaR > 0 && (custosFixos / ultimo.valorFaturaR) > 0.6) {
      alertas.add({
        'tipo': 'custo_fixo_alto',
        'titulo': 'Custos Fixos Elevados',
        'mensagem':
            'Mais de 60% da sua fatura em ${usina.nome} é composta por Demanda ou Taxas. A energia solar não abate estes custos.',
        'cor': 'orange',
        'icone': 'domain',
      });
    }

    final boxLanc = Hive.box<LancamentoMensal>('lancamentos');
    final historico =
        boxLanc.values
            .where((l) => l.usinaId == usina.id && !l.isDeletado)
            .toList()
          ..sort((a, b) => b.dataReferencia.compareTo(a.dataReferencia));

    if (usina.isGeradora) {
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

    double creditoRecebidoNoMes = _calcularCreditoRecebidoLiquido(
      usina,
      ultimo,
    );
    double consumo = ultimo.energiaConsumidaRedeKwh;

    // Calcula o que a Concessionária reteve
    double taxaMinima = _obterCustoDisponibilidade(usina);
    double consumoAbativel = consumo > taxaMinima ? consumo - taxaMinima : 0.0;

    double saldoMensal = creditoRecebidoNoMes - consumoAbativel;

    if (saldoMensal < 0) {
      double deficit = saldoMensal.abs();
      // O global já conta com a subtração do mês atual que a MetricasGerais fez
      if (saldoCreditosGlobal + deficit >= deficit) {
        // Verifica se havia saldo antes do desconto
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

    // --- ALERTA PRO 3: O AUDITOR IMPLACÁVEL DE CRÉDITOS ---
    if (historico.length >= 2 && ultimo.saldoInformadoNaFatura != null) {
      final mesAnterior = historico[1]; // O penúltimo da lista

      if (mesAnterior.saldoInformadoNaFatura != null) {
        double saldoAnterior = mesAnterior.saldoInformadoNaFatura!;

        // A matemática física do que aconteceu neste mês:
        double saldoMatematicoEsperado = saldoAnterior + saldoMensal;

        if (saldoMatematicoEsperado < 0) {
          saldoMatematicoEsperado = 0;
        }

        double saldoLidoNaFaturaAtual = ultimo.saldoInformadoNaFatura!;

        if (saldoMatematicoEsperado - saldoLidoNaFaturaAtual > 5.0) {
          double creditosDesviados =
              saldoMatematicoEsperado - saldoLidoNaFaturaAtual;
          alertas.add({
            'tipo': 'creditos_desviados',
            'titulo': '🚨 ALERTA: Créditos Desviados!',
            'mensagem':
                'Auditoria Falhou: No mês passado você tinha ${saldoAnterior.toStringAsFixed(0)} kWh. Neste mês o seu saldo (sobra menos consumo) foi de ${(saldoMensal > 0 ? "+" : "")}${saldoMensal.toStringAsFixed(0)} kWh. \n\nO seu saldo correto deveria ser ${saldoMatematicoEsperado.toStringAsFixed(0)} kWh, mas a concessionária computou apenas ${saldoLidoNaFaturaAtual.toStringAsFixed(0)} kWh. Faltam ${creditosDesviados.toStringAsFixed(0)} kWh. Conteste a sua fatura!',
            'cor': 'red',
            'icone': 'policy',
          });
        }
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

    double potenciaEfetivaInstalada = calcularPotenciaEfetiva(usina);

    lancamentos.sort((a, b) => a.dataReferencia.compareTo(b.dataReferencia));
    double anosDeUso =
        DateTime.now().difference(lancamentos.first.dataReferencia).inDays /
        365.0;

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

  static double estimarProducaoIdealMensal(Usina usina) {
    return calcularPotenciaEfetiva(usina) * 120.0;
  }

  // ===========================================================================
  // 5. HELPERS DE AUDITORIA
  // ===========================================================================
  static double obterTotalDistribuidoNoMes(
    Usina geradora,
    LancamentoMensal lancamentoMae,
  ) {
    if (!geradora.isGeradora || geradora.beneficiarias.isEmpty) {
      return 0.0;
    }
    double percentualTotalEnviado = geradora.beneficiarias.fold(
      0.0,
      (sum, b) => sum + b.percentual,
    );
    return lancamentoMae.energiaInjetadaKwh * (percentualTotalEnviado / 100);
  }

  static double obterCreditoRepassadoParaFilha(
    Usina geradora,
    LancamentoMensal lancamentoMae,
    String idUsinaFilha,
  ) {
    if (!geradora.isGeradora) {
      return 0.0;
    }
    try {
      final vinculo = geradora.beneficiarias.firstWhere(
        (b) => b.idUsinaFilha == idUsinaFilha,
      );
      return lancamentoMae.energiaInjetadaKwh * (vinculo.percentual / 100);
    } catch (e) {
      return 0.0;
    }
  }

  // ===========================================================================
  // 6. MOTOR DE OTIMIZAÇÃO (O "DINHEIRO NA MESA")
  // ===========================================================================
  static List<Map<String, dynamic>> gerarAlertaDeOtimizacaoDeRateio() {
    List<Map<String, dynamic>> alertasGerais = [];

    final boxUsinas = Hive.box<Usina>('usinas');
    final boxLancamentos = Hive.box<LancamentoMensal>('lancamentos');

    final todasUsinas = boxUsinas.values
        .where((u) => u.ativa && !u.isDeletado)
        .toList();
    final beneficiarias = todasUsinas.where((u) => !u.isGeradora).toList();
    final geradoras = todasUsinas.where((u) => u.isGeradora).toList();

    Map<String, double> saldoDasMaes = {};
    for (var mae in geradoras) {
      var lancamentosMae = boxLancamentos.values
          .where((l) => l.usinaId == mae.id && !l.isDeletado)
          .toList();
      var metricasMae = calcularMetricasGerais(mae, lancamentosMae);
      saldoDasMaes[mae.id] = metricasMae.saldoCreditosEstimado;
    }

    for (var filha in beneficiarias) {
      var lancamentosFilha = boxLancamentos.values
          .where((l) => l.usinaId == filha.id && !l.isDeletado)
          .toList();

      if (lancamentosFilha.isNotEmpty) {
        lancamentosFilha.sort(
          (a, b) => b.dataReferencia.compareTo(a.dataReferencia),
        );
        var ultimoLancamento = lancamentosFilha.first;

        double taxaMinima = _obterCustoDisponibilidade(filha);
        double consumoAbativel =
            ultimoLancamento.energiaConsumidaRedeKwh > taxaMinima
            ? ultimoLancamento.energiaConsumidaRedeKwh - taxaMinima
            : 0.0;

        double deficitDoMes =
            consumoAbativel - ultimoLancamento.energiaInjetadaKwh;

        if (deficitDoMes > 0) {
          for (var mae in geradoras) {
            if (mae.beneficiarias.any((b) => b.idUsinaFilha == filha.id)) {
              if (saldoDasMaes[mae.id] != null &&
                  saldoDasMaes[mae.id]! > deficitDoMes) {
                alertasGerais.add({
                  'tipo': 'otimizacao_rateio',
                  'titulo': 'Oportunidade de Economia!',
                  'mensagem':
                      'A unidade **${filha.nome}** pagou conta este mês, enquanto a usina **${mae.nome}** tem saldo sobrando.\nRecomendação: Aumente o % de rateio para a ${filha.nome}!',
                  'cor': 'green',
                  'icone': 'lightbulb_circle',
                });
              }
            }
          }
        }
      }
    }

    return alertasGerais;
  }
}
