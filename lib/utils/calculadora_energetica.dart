// Caminho: lib/utils/calculadora_energetica.dart
// Descrição: Motor de cálculo energético (Com Inteligência Tarifária, Regra de Excedente ANEEL, Auditoria, Multas e Créditos de Terceiros).

import 'package:hive/hive.dart';
import '../models/usina.dart';
import '../models/lancamento.dart';

// --- CLASSES DE DADOS (Contêineres de Resultados) ---

// NOVO: Pacote Oficial de Dados do Mês (A Fonte Única da Verdade)
class ResumoMesOficial {
  final double geracaoTotal;
  final double autoconsumo;
  final double consumoRealLocal;
  final double consumidoDaRede;
  final double injetadoOuRecebido;
  final double taxaMinimaRetida;
  final double sobraFisicaDoMes; // Excedente final após deduções e rateios
  final double saldoAcumuladoExibicao;
  final bool isSaldoEstimado;

  ResumoMesOficial({
    required this.geracaoTotal,
    required this.autoconsumo,
    required this.consumoRealLocal,
    required this.consumidoDaRede,
    required this.injetadoOuRecebido,
    required this.taxaMinimaRetida,
    required this.sobraFisicaDoMes,
    required this.saldoAcumuladoExibicao,
    required this.isSaldoEstimado,
  });
}

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

  // --- HELPER: FILTRO DE HISTÓRICO DE VIGÊNCIA ---
  static Iterable<BeneficiariaItem> _obterBeneficiariasVigentes(
    Usina usina,
    DateTime dataFatura,
  ) {
    DateTime dataRef = DateTime(
      dataFatura.year,
      dataFatura.month,
      dataFatura.day,
    );

    return usina.beneficiarias.where((b) {
      DateTime inicio = DateTime(
        b.dataInicio.year,
        b.dataInicio.month,
        b.dataInicio.day,
      );
      bool aposInicio =
          dataRef.isAfter(inicio) || dataRef.isAtSameMomentAs(inicio);

      bool antesDoFim = true;
      if (b.dataFim != null) {
        DateTime fim = DateTime(
          b.dataFim!.year,
          b.dataFim!.month,
          b.dataFim!.day,
        );
        antesDoFim = dataRef.isBefore(fim) || dataRef.isAtSameMomentAs(fim);
      }

      return aposInicio && antesDoFim;
    });
  }

  // --- NOVO HELPER ANEEL: CALCULA O EXCEDENTE DA GERADORA ---
  static double _calcularExcedenteParaRateio(
    Usina geradora,
    LancamentoMensal l,
  ) {
    double custoDisp = _obterCustoDisponibilidade(geradora);

    // Calcula quanto da energia consumida pode ser compensada
    double consumoAbativel = l.energiaConsumidaRedeKwh > custoDisp
        ? l.energiaConsumidaRedeKwh - custoDisp
        : 0.0;

    // O excedente é a injeção menos o que a geradora já engoliu para ela mesma
    double excedente = l.energiaInjetadaKwh - consumoAbativel;

    return excedente > 0 ? excedente : 0.0;
  }

  // --- HELPER CENTRALIZADO PARA EVITAR REPETIÇÃO DE CÓDIGO ---
  static double _calcularCreditoRecebidoLiquido(
    Usina usina,
    LancamentoMensal l,
  ) {
    if (usina.isGeradora) {
      var vigentes = _obterBeneficiariasVigentes(usina, l.dataReferencia);
      double percentualEnviado = vigentes.fold(
        0.0,
        (sum, b) => sum + b.percentual,
      );

      // REGRA ANEEL: O rateio é sobre o EXCEDENTE (a sobra), não sobre o total injetado
      double excedente = _calcularExcedenteParaRateio(usina, l);
      double energiaEnviadaParaFilhas = excedente * (percentualEnviado / 100);

      // A geradora retém a injeção original MENOS a energia que ela exportou
      return l.energiaInjetadaKwh - energiaEnviadaParaFilhas;
    } else {
      // -------------------------------------------------------------
      // REGRA DE OURO DA BENEFICIÁRIA (ATUALIZADA)
      // -------------------------------------------------------------
      double recebidoLocal = l.energiaInjetadaKwh;

      // PRIORIDADE 1: Se temos o crédito real explícito informado (pela IA ou Manualmente), usamos ele!
      if (l.creditosRecebidosDeTerceiros != null &&
          l.creditosRecebidosDeTerceiros! > 0) {
        return recebidoLocal + l.creditosRecebidosDeTerceiros!;
      }

      // PRIORIDADE 2 (FALLBACK): Não tem explícito? Calcula a teoria com base na Usina Mãe (Para faturas antigas)
      double recebidoTeorico = 0;
      final boxUsinas = Hive.box<Usina>('usinas');
      final boxLancamentos = Hive.box<LancamentoMensal>('lancamentos');
      final maes = boxUsinas.values.where((u) => u.isGeradora);

      for (var mae in maes) {
        try {
          var vigentesDaMae = _obterBeneficiariasVigentes(
            mae,
            l.dataReferencia,
          );
          var vinculo = vigentesDaMae.firstWhere(
            (b) => b.idUsinaFilha == usina.id,
          );

          var lancMae = boxLancamentos.values.firstWhere(
            (lm) =>
                lm.usinaId == mae.id &&
                lm.dataReferencia.year == l.dataReferencia.year &&
                lm.dataReferencia.month == l.dataReferencia.month &&
                !lm.isDeletado,
          );

          // REGRA ANEEL: A filha recebe um percentual do EXCEDENTE da mãe
          double excedenteMae = _calcularExcedenteParaRateio(mae, lancMae);
          recebidoTeorico += (excedenteMae * (vinculo.percentual / 100));
        } catch (_) {}
      }
      return recebidoLocal + recebidoTeorico;
    }
  }

  // ===========================================================================
  // A NOVA FONTE ÚNICA DE VERDADE (SINGLE SOURCE OF TRUTH)
  // ===========================================================================
  static ResumoMesOficial gerarResumoMesOficial(
    Usina usina,
    LancamentoMensal lancamento,
  ) {
    double taxaMin = _obterCustoDisponibilidade(usina);
    double geracao = usina.isGeradora ? lancamento.geracaoTotalKwh : 0.0;
    double injetadoReal = lancamento.energiaInjetadaKwh;

    // 1. Autoconsumo: Só existe se gerou mais do que injetou na rede
    double autoconsumo = usina.isGeradora
        ? (geracao - injetadoReal).clamp(0.0, double.infinity)
        : 0.0;

    // 2. Consumo Físico no Local
    double consumoRede = lancamento.energiaConsumidaRedeKwh;
    double consumoRealLocal = autoconsumo + consumoRede;

    // 3. Taxa Mínima Cobrada Pela Concessionária
    double taxaMinimaRetida = consumoRede < taxaMin ? consumoRede : taxaMin;

    // 4. Crédito que entrou no mês para a Unidade
    double creditoRecebidoLiquido = _calcularCreditoRecebidoLiquido(
      usina,
      lancamento,
    );

    // 5. Consumo que pode ser abatido
    double consumoAbativel = consumoRede > taxaMin
        ? consumoRede - taxaMin
        : 0.0;

    // 6. A Sobra Física de Créditos (Vai alimentar o saldo ou consumir dele)
    double sobraFisicaDoMes = creditoRecebidoLiquido - consumoAbativel;

    // 7. Cálculo do Saldo Final
    double saldoExibicao = lancamento.saldoInformadoNaFatura ?? 0.0;
    bool isEstimado = false;

    if (saldoExibicao == 0.0) {
      final boxLanc = Hive.box<LancamentoMensal>('lancamentos');
      final historico = boxLanc.values
          .where((l) => l.usinaId == usina.id && !l.isDeletado)
          .toList();

      historico.sort((a, b) => a.dataReferencia.compareTo(b.dataReferencia));

      int idx = historico.indexWhere((l) => l.id == lancamento.id);
      if (idx > 0) {
        double saldoAnterior = historico[idx - 1].saldoInformadoNaFatura ?? 0.0;
        saldoExibicao = (saldoAnterior + sobraFisicaDoMes).clamp(
          0.0,
          double.infinity,
        );
      } else {
        saldoExibicao = sobraFisicaDoMes > 0 ? sobraFisicaDoMes : 0.0;
      }
      isEstimado = true;
    }

    // 8. O que mostrar na UI para "Exportou" (Geradora) ou "Recebeu" (Beneficiária)
    double injetadoOuRecebidoUi = usina.isGeradora
        ? injetadoReal
        : creditoRecebidoLiquido;

    return ResumoMesOficial(
      geracaoTotal: geracao,
      autoconsumo: autoconsumo,
      consumoRealLocal: consumoRealLocal,
      consumidoDaRede: consumoRede,
      injetadoOuRecebido: injetadoOuRecebidoUi,
      taxaMinimaRetida: taxaMinimaRetida,
      sobraFisicaDoMes: sobraFisicaDoMes,
      saldoAcumuladoExibicao: saldoExibicao,
      isSaldoEstimado: isEstimado,
    );
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

      if (l.saldoInformadoNaFatura != null) {
        double diferenca = saldoRollingKwh - l.saldoInformadoNaFatura!;
        if (diferenca > 5.0) {
          somaDesviosConcessionaria += diferenca;
        }
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

    var vigentes = _obterBeneficiariasVigentes(
      geradora,
      lancamentoGeradora.dataReferencia,
    );
    double excedenteParaRateio = _calcularExcedenteParaRateio(
      geradora,
      lancamentoGeradora,
    );

    for (var vinculo in vigentes) {
      // REGRA ANEEL APLICADA NO BALANÇO MENSAL:
      double creditoDireito = excedenteParaRateio * (vinculo.percentual / 100);

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

    double percentualTotalFilhas = vigentes.fold(
      0.0,
      (sum, b) => sum + b.percentual,
    );
    double percGeradora = 100 - percentualTotalFilhas;

    if (percGeradora > 0) {
      double energiaEnviadaParaFilhas =
          excedenteParaRateio * (percentualTotalFilhas / 100);

      // O que sobra pra Geradora é tudo que ela injetou, menos o que exportou pras filhas
      double creditoGeradoraTotal =
          lancamentoGeradora.energiaInjetadaKwh - energiaEnviadaParaFilhas;

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
          creditoRecebido: creditoGeradoraTotal,
          consumoReal: lancamentoGeradora.energiaConsumidaRedeKwh,
          // O Saldo da geradora é o que restou após exportar e APÓS abater o próprio consumo
          saldo: creditoGeradoraTotal - consumoAbativelGeradora,
        ),
      );
    }

    return RelatorioMensal(
      geracaoTotal: lancamentoGeradora.geracaoTotalKwh,
      injecaoTotal: lancamentoGeradora.energiaInjetadaKwh,
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
        'titulo': 'Custos Fixos Elevados para ${usina.nome}',
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

    double taxaMinima = _obterCustoDisponibilidade(usina);
    double consumoAbativel = consumo > taxaMinima ? consumo - taxaMinima : 0.0;

    double saldoMensal = creditoRecebidoNoMes - consumoAbativel;

    if (saldoMensal < 0) {
      double deficit = saldoMensal.abs();
      double saldoDoMesAnterior = 0.0;
      if (historico.length >= 2) {
        saldoDoMesAnterior = historico[1].saldoInformadoNaFatura ?? 0.0;
      }

      if (saldoDoMesAnterior >= deficit) {
        alertas.add({
          'tipo': 'consumo_reserva',
          'titulo': 'Consumindo Reserva em ${usina.nome}',
          'mensagem':
              'A unidade ${usina.nome} consumiu mais do que recebeu neste mês. O sistema utilizou ${deficit.toStringAsFixed(0)} kWh do seu Banco de Créditos para cobrir a diferença.',
          'cor': 'orange',
          'icone': 'hourglass_bottom',
        });
      } else if (saldoDoMesAnterior > 1.0) {
        double faltou = deficit - saldoDoMesAnterior;
        alertas.add({
          'tipo': 'deficit_parcial',
          'titulo': 'Reserva Insuficiente para ${usina.nome}',
          'mensagem':
              'A unidade ${usina.nome} precisou de ${deficit.toStringAsFixed(0)} kWh extras. A sua reserva só tinha ${saldoDoMesAnterior.toStringAsFixed(0)} kWh, então a diferença de ${faltou.toStringAsFixed(0)} kWh foi cobrada em Reais.',
          'cor': 'red',
          'icone': 'monetization_on',
        });
      } else {
        alertas.add({
          'tipo': 'deficit_real',
          'titulo': 'Fatura Descoberta (Pagamento Extra)',
          'mensagem':
              'A unidade ${usina.nome} precisou de ${deficit.toStringAsFixed(0)} kWh extras para abater o consumo. Como você NÃO tinha saldo, a diferença foi cobrada em Reais na fatura.',
          'cor': 'red',
          'icone': 'monetization_on',
        });
      }
    }

    if (historico.length >= 2 && ultimo.saldoInformadoNaFatura != null) {
      final mesAnterior = historico[1];

      if (mesAnterior.saldoInformadoNaFatura != null) {
        double saldoAnterior = mesAnterior.saldoInformadoNaFatura!;
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
            'titulo': 'Créditos não lançados para ${usina.nome}!',
            'mensagem':
                'A concessionária deixou de creditar  ${creditosDesviados.toStringAsFixed(0)} kWh no seu banco de créditos para a unidade ${usina.nome}.\n'
                '• Saldo Total Esperado: ${saldoMatematicoEsperado.toStringAsFixed(0)} kWh.\n'
                'Verifique e conteste a sua fatura!',
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
    var vigentes = _obterBeneficiariasVigentes(
      geradora,
      lancamentoMae.dataReferencia,
    );
    double percentualTotalEnviado = vigentes.fold(
      0.0,
      (sum, b) => sum + b.percentual,
    );
    double excedente = _calcularExcedenteParaRateio(geradora, lancamentoMae);
    return excedente * (percentualTotalEnviado / 100);
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
      var vigentes = _obterBeneficiariasVigentes(
        geradora,
        lancamentoMae.dataReferencia,
      );
      final vinculo = vigentes.firstWhere(
        (b) => b.idUsinaFilha == idUsinaFilha,
      );
      double excedente = _calcularExcedenteParaRateio(geradora, lancamentoMae);
      return excedente * (vinculo.percentual / 100);
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
            var vigentesNaMae = _obterBeneficiariasVigentes(
              mae,
              ultimoLancamento.dataReferencia,
            );

            if (vigentesNaMae.any((b) => b.idUsinaFilha == filha.id)) {
              if (saldoDasMaes[mae.id] != null &&
                  saldoDasMaes[mae.id]! > deficitDoMes) {
                alertasGerais.add({
                  'tipo': 'otimizacao_rateio',
                  'titulo': 'Oportunidade de Economia ! ${filha.nome}',
                  'mensagem':
                      'A unidade ${filha.nome} pagou conta este mês, enquanto a usina ${mae.nome} tem saldo sobrando.\nRecomendação: Aumente o % de rateio para a ${filha.nome}!',
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
