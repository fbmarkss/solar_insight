// Caminho: lib/utils/calculadora_energetica.dart
// Descrição: Motor de cálculo energético ANEEL + Auditoria Fiscalizadora +
//            Validade de Créditos em 60 meses + Inteligência Tarifária + Alertas.
// Versão: V4.0 — ARQUITETURA DTO (Adicionada) + REGRA GD II
// - CORREÇÃO LINTER: Chaves adicionadas nos if statements.
// - MANTIDO: 100% das funções originais (nada foi removido).
// - ADICIONADO: Classe ProcessamentoCiclo e método analisarCiclo para o futuro.
// - ATUALIZADO: calcularEconomiaFinanceiraMensal agora reflete GD II.

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/usina.dart';
import '../models/lancamento.dart';

class ResumoMesOficial {
  final double geracaoTotal;
  final double autoconsumo;
  final double consumoRealLocal;
  final double consumidoDaRede;
  final double injetadoOuRecebido;
  final double taxaMinimaRetida;
  final double sobraFisicaDoMes;
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
  final double custoFixoInevitavelR;
  final double totalMultasReativoR;
  final double totalCreditosDesviados;
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

// NOVO: DTO para quando as telas forem atualizadas
class ProcessamentoCiclo {
  final double geracaoTotal;
  final double consumoTotal;
  final double injetadoNaRede;
  final double recebidoDeTerceiros;
  final double autoconsumo;
  final double consumoRealLocal;
  final double consumoAbativel;
  final double taxaMinimaRetida;
  final double totalCreditosDisponiveisNoMes;
  final double sobraFisicaDoMes;
  final double saldoAcumuladoExibicao;
  final bool isSaldoEstimado;
  final double tarifaAplicada;
  final double economiaAutoconsumo;
  final double economiaCompensada;
  final double economiaTotalReais;
  final List<Map<String, dynamic>> alertas;

  ProcessamentoCiclo({
    required this.geracaoTotal,
    required this.consumoTotal,
    required this.injetadoNaRede,
    required this.recebidoDeTerceiros,
    required this.autoconsumo,
    required this.consumoRealLocal,
    required this.consumoAbativel,
    required this.taxaMinimaRetida,
    required this.totalCreditosDisponiveisNoMes,
    required this.sobraFisicaDoMes,
    required this.saldoAcumuladoExibicao,
    required this.isSaldoEstimado,
    required this.tarifaAplicada,
    required this.economiaAutoconsumo,
    required this.economiaCompensada,
    required this.economiaTotalReais,
    required this.alertas,
  });
}

class CalculadoraEnergetica {
  // ===========================================================================
  // CONSTANTES INTERNAS
  // ===========================================================================
  static const double _kSaldoMinimoRelevante = 5.0;
  static const double _kToleranciaAuditoriaAneel = 5.0;
  static const int _kMesesValidadeCredito = 60;
  static const double _kFatorRendimentoGD2 = 0.85; // Adicionado para GD II

  // ===========================================================================
  // HELPERS PRIVADOS
  // ===========================================================================

  static double _obterConsumoTotal(LancamentoMensal l) {
    return l.energiaConsumidaRedeKwh +
        (l.consumoReservado ?? 0.0) +
        (l.consumoPonta ?? 0.0) +
        (l.consumoForaPonta ?? 0.0);
  }

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

  static double _calcularExcedenteParaRateio(
    Usina geradora,
    LancamentoMensal l,
  ) {
    double consumoTotal = _obterConsumoTotal(l);
    double custoDisp = _obterCustoDisponibilidade(geradora);

    double usoLocalAneel = consumoTotal > custoDisp
        ? consumoTotal - custoDisp
        : 0.0;

    double excedente = l.energiaInjetadaKwh - usoLocalAneel;
    return excedente > 0 ? excedente : 0.0;
  }

  // ===========================================================================
  // AUDITORIA FISCALIZADORA (PÚBLICO)
  // ===========================================================================
  static double auditarAneelContraFatura(Usina usina, LancamentoMensal l) {
    if (l.saldoInformadoNaFatura == null) return 0.0;

    double? saldoAnterior;
    try {
      final boxLanc = Hive.box<LancamentoMensal>('lancamentos');
      final historico =
          boxLanc.values
              .where((lanc) => lanc.usinaId == usina.id && !lanc.isDeletado)
              .toList()
            ..sort((a, b) => a.dataReferencia.compareTo(b.dataReferencia));

      final mesAtual = DateTime(l.dataReferencia.year, l.dataReferencia.month);

      for (var i = historico.length - 1; i >= 0; i--) {
        final lanc = historico[i];
        final mesLanc = DateTime(
          lanc.dataReferencia.year,
          lanc.dataReferencia.month,
        );
        if (mesLanc.isBefore(mesAtual) &&
            (lanc.saldoInformadoNaFatura ?? 0) > 0) {
          saldoAnterior = lanc.saldoInformadoNaFatura;
          break;
        }
      }
    } catch (e) {
      debugPrint('[V3.4] Falha ao buscar saldo anterior: $e');
    }

    if (saldoAnterior == null || saldoAnterior <= 0) return 0.0;

    double saidaDoEstoque =
        (saldoAnterior + l.energiaInjetadaKwh) - l.saldoInformadoNaFatura!;

    double consumoTotal = _obterConsumoTotal(l);
    double custoDisp = _obterCustoDisponibilidade(usina);
    double usoLocalAneel = consumoTotal > custoDisp
        ? consumoTotal - custoDisp
        : 0.0;

    var vigentes = _obterBeneficiariasVigentes(usina, l.dataReferencia);
    double percEnviado = vigentes.fold(0.0, (s, b) => s + b.percentual);
    double excedenteAneel = l.energiaInjetadaKwh - usoLocalAneel;

    // CORREÇÃO DO LINTER: Inserido chaves
    if (excedenteAneel < 0) {
      excedenteAneel = 0.0;
    }

    double repasseAneel = excedenteAneel * (percEnviado / 100);

    double saidaEsperadaAneel = usoLocalAneel + repasseAneel;
    double divergencia = (saidaDoEstoque - saidaEsperadaAneel).abs();

    if (divergencia <= _kToleranciaAuditoriaAneel) return 0.0;

    final double tetoFisico = l.energiaInjetadaKwh * 0.5;
    if (tetoFisico > 0 && divergencia > tetoFisico) {
      debugPrint(
        '[V3.4] Divergência absurda descartada: '
        '${divergencia.toStringAsFixed(1)} kWh '
        '(injetado: ${l.energiaInjetadaKwh} kWh).',
      );
      return 0.0;
    }

    return divergencia;
  }

  // ===========================================================================
  // COTA DA TAXA MÍNIMA DA FILHA (PÚBLICO)
  // ===========================================================================
  static double calcularCotaTaxaMinimaFilha(
    Usina filha,
    DateTime dataReferencia,
  ) {
    final boxUsinas = Hive.box<Usina>('usinas');
    double cotaMaxima = 0.0;

    final maes = boxUsinas.values.where(
      (u) =>
          u.isGeradora &&
          !u.isDeletado &&
          u.beneficiarias.any((b) => b.idUsinaFilha == filha.id),
    );

    for (var mae in maes) {
      try {
        final vigentes = _obterBeneficiariasVigentes(mae, dataReferencia);
        final vinculo = vigentes.firstWhere((b) => b.idUsinaFilha == filha.id);
        final taxaMinima = _obterCustoDisponibilidade(mae);
        final cota = taxaMinima * (vinculo.percentual / 100);

        // CORREÇÃO DO LINTER: Inserido chaves
        if (cota > cotaMaxima) {
          cotaMaxima = cota;
        }
      } catch (e) {
        debugPrint('[V3.4] Erro ao calcular cota da taxa mínima: $e');
      }
    }

    return cotaMaxima;
  }

  // ===========================================================================
  // RESOLUÇÃO DE TARIFA (PÚBLICO)
  // ===========================================================================
  static double resolverTarifaAplicavel(LancamentoMensal l) {
    double tarifa = l.tarifaKwh;

    if (l.grupoTarifario == 'A' ||
        l.modalidadeTarifaria == 'VERDE' ||
        l.modalidadeTarifaria == 'AZUL') {
      if ((l.tarifaTeForaPonta ?? 0) > 0) {
        tarifa = l.tarifaTeForaPonta! + (l.tarifaTusdForaPonta ?? 0);
      }
    } else {
      if ((l.tarifaTeUnica ?? 0) > 0) {
        tarifa = l.tarifaTeUnica! + (l.tarifaTusdUnica ?? 0);
      }
    }
    if (tarifa <= 0) {
      tarifa = l.tarifaKwh;
    }
    return tarifa;
  }

  // ===========================================================================
  // ECONOMIA FINANCEIRA MENSAL (PÚBLICO)
  // * ATUALIZADO COM MATEMÁTICA GD II
  // ===========================================================================
  static double calcularEconomiaFinanceiraMensal(
    Usina usina,
    LancamentoMensal l,
  ) {
    double tarifa = resolverTarifaAplicavel(l);

    double autoconsumo = (l.geracaoTotalKwh - l.energiaInjetadaKwh).clamp(
      0.0,
      double.infinity,
    );
    double creditosTotaisDisponiveis =
        l.energiaInjetadaKwh + (l.creditosRecebidosDeTerceiros ?? 0.0);

    double energiaCompensada = creditosTotaisDisponiveis.clamp(
      0.0,
      l.energiaConsumidaRedeKwh,
    );

    // REGRA HÍBRIDA GD I / GD II: Autoconsumo economiza 100%, Compensado economiza ~85%
    double economiaAutoconsumo = autoconsumo * tarifa;
    double economiaCompensada =
        energiaCompensada * (tarifa * _kFatorRendimentoGD2);

    return economiaAutoconsumo + economiaCompensada;
  }

  // ===========================================================================
  // CRÉDITO LÍQUIDO RECEBIDO (interno)
  // ===========================================================================
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

      double excedente = _calcularExcedenteParaRateio(usina, l);
      double energiaEnviadaParaFilhas = excedente * (percentualEnviado / 100);

      double recebidoLocal = l.energiaInjetadaKwh;
      double creditosExternos = l.creditosRecebidosDeTerceiros ?? 0.0;

      return (recebidoLocal + creditosExternos) - energiaEnviadaParaFilhas;
    } else {
      double recebidoLocal = l.energiaInjetadaKwh;

      if (l.creditosRecebidosDeTerceiros != null &&
          l.creditosRecebidosDeTerceiros! > 0) {
        return recebidoLocal + l.creditosRecebidosDeTerceiros!;
      }

      double recebidoTeorico = 0;
      final boxUsinas = Hive.box<Usina>('usinas');
      final boxLancamentos = Hive.box<LancamentoMensal>('lancamentos');
      final maes = boxUsinas.values.where((u) => u.isGeradora);

      int mesBuscaMae = l.dataReferencia.month - 1;
      int anoBuscaMae = l.dataReferencia.year;
      if (mesBuscaMae == 0) {
        mesBuscaMae = 12;
        anoBuscaMae -= 1;
      }

      for (var mae in maes) {
        try {
          var vigentesDaMae = _obterBeneficiariasVigentes(
            mae,
            l.dataReferencia,
          );
          final vinculo = vigentesDaMae.firstWhere(
            (b) => b.idUsinaFilha == usina.id,
          );

          var lancMae = boxLancamentos.values.firstWhere(
            (lm) =>
                lm.usinaId == mae.id &&
                lm.dataReferencia.year == anoBuscaMae &&
                lm.dataReferencia.month == mesBuscaMae &&
                !lm.isDeletado,
          );

          double excedenteMae = _calcularExcedenteParaRateio(mae, lancMae);
          recebidoTeorico += (excedenteMae * (vinculo.percentual / 100));
        } catch (e) {
          debugPrint('[V3.4] Falha ao calcular crédito teórico: $e');
        }
      }
      return recebidoLocal + recebidoTeorico;
    }
  }

  // ===========================================================================
  // RESUMO MENSAL OFICIAL
  // ===========================================================================
  static ResumoMesOficial gerarResumoMesOficial(
    Usina usina,
    LancamentoMensal lancamento,
  ) {
    double taxaMin = _obterCustoDisponibilidade(usina);
    double geracao = usina.isGeradora ? lancamento.geracaoTotalKwh : 0.0;
    double injetadoReal = lancamento.energiaInjetadaKwh;

    double autoconsumo = usina.isGeradora
        ? (geracao - injetadoReal).clamp(0.0, double.infinity)
        : 0.0;

    double consumoRedeTotal = _obterConsumoTotal(lancamento);
    double consumoRealLocal = autoconsumo + consumoRedeTotal;

    double taxaMinimaRetida = consumoRedeTotal < taxaMin
        ? consumoRedeTotal
        : taxaMin;

    double creditoRecebidoLiquido = _calcularCreditoRecebidoLiquido(
      usina,
      lancamento,
    );

    double consumoAbativel = consumoRedeTotal > taxaMin
        ? consumoRedeTotal - taxaMin
        : 0.0;

    double sobraFisicaDoMes = creditoRecebidoLiquido - consumoAbativel;

    double saldoExibicao = lancamento.saldoInformadoNaFatura ?? 0.0;
    bool isEstimado = false;

    if (saldoExibicao == 0.0) {
      final boxLanc = Hive.box<LancamentoMensal>('lancamentos');
      final historico =
          boxLanc.values
              .where((l) => l.usinaId == usina.id && !l.isDeletado)
              .toList()
            ..sort((a, b) => a.dataReferencia.compareTo(b.dataReferencia));

      int idx = historico.indexWhere((l) => l.id == lancamento.id);
      if (idx > 0) {
        double saldoAnteriorEstimado = _calcularSaldoValidoAteData(
          usina,
          historico,
          idx,
        );
        saldoExibicao = (saldoAnteriorEstimado + sobraFisicaDoMes).clamp(
          0.0,
          double.infinity,
        );
      } else {
        saldoExibicao = sobraFisicaDoMes > 0 ? sobraFisicaDoMes : 0.0;
      }
      isEstimado = true;
    }

    double injetadoOuRecebidoUi = usina.isGeradora
        ? injetadoReal + (lancamento.creditosRecebidosDeTerceiros ?? 0.0)
        : creditoRecebidoLiquido;

    return ResumoMesOficial(
      geracaoTotal: geracao,
      autoconsumo: autoconsumo,
      consumoRealLocal: consumoRealLocal,
      consumidoDaRede: consumoRedeTotal,
      injetadoOuRecebido: injetadoOuRecebidoUi,
      taxaMinimaRetida: taxaMinimaRetida,
      sobraFisicaDoMes: sobraFisicaDoMes,
      saldoAcumuladoExibicao: saldoExibicao,
      isSaldoEstimado: isEstimado,
    );
  }

  static double _calcularSaldoValidoAteData(
    Usina usina,
    List<LancamentoMensal> historicoOrdenado,
    int ateIdx,
  ) {
    final List<_LoteCredito> lotes = [];

    for (int i = 0; i < ateIdx; i++) {
      final l = historicoOrdenado[i];

      final int mesAtualAbsoluto =
          l.dataReferencia.year * 12 + l.dataReferencia.month;
      lotes.removeWhere(
        (lote) =>
            (mesAtualAbsoluto - lote.mesAbsoluto) >= _kMesesValidadeCredito,
      );

      double entradaCredito = _calcularCreditoRecebidoLiquido(usina, l);
      double consumoTotal = _obterConsumoTotal(l);
      double custoDisp = _obterCustoDisponibilidade(usina);
      double consumoAbativel = consumoTotal > custoDisp
          ? consumoTotal - custoDisp
          : 0.0;

      double aConsumir = consumoAbativel;
      while (aConsumir > 0 && lotes.isNotEmpty) {
        final lote = lotes.first;
        if (lote.kwh <= aConsumir) {
          aConsumir -= lote.kwh;
          lotes.removeAt(0);
        } else {
          lote.kwh -= aConsumir;
          aConsumir = 0;
        }
      }

      if (entradaCredito > 0) {
        lotes.add(
          _LoteCredito(mesAbsoluto: mesAtualAbsoluto, kwh: entradaCredito),
        );
      }
    }

    double saldo = 0;
    for (final lote in lotes) {
      saldo += lote.kwh;
    }
    return saldo > 0 ? saldo : 0.0;
  }

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

  static MetricasGerais calcularMetricasGerais(
    Usina usina,
    List<LancamentoMensal> historico,
  ) {
    final historicoOrdenado = List<LancamentoMensal>.from(historico)
      ..sort((a, b) => a.dataReferencia.compareTo(b.dataReferencia));

    double somaGeracao = 0;
    double somaInjetadaHistorico = 0;
    double somaEconomiaReais = 0;
    double saldoRollingKwh = 0;

    double somaCustosFixos = 0;
    double somaMultas = 0;
    double somaDesviosConcessionaria = 0;

    double custoDisponibilidade = _obterCustoDisponibilidade(usina);

    final List<_LoteCredito> lotes = [];

    for (var l in historicoOrdenado) {
      final int mesAtualAbsoluto =
          l.dataReferencia.year * 12 + l.dataReferencia.month;
      lotes.removeWhere(
        (lote) =>
            (mesAtualAbsoluto - lote.mesAbsoluto) >= _kMesesValidadeCredito,
      );

      double entradaCreditoMesParaSaldo = _calcularCreditoRecebidoLiquido(
        usina,
        l,
      );
      double consumoMesTotal = _obterConsumoTotal(l);

      double tarifaInteligente = resolverTarifaAplicavel(l);

      somaCustosFixos += l.custoDemandaR + (l.custoIluminacaoPublica ?? 0.0);
      somaMultas += (l.multaReativo ?? 0.0);

      if (usina.isGeradora) {
        somaGeracao += l.geracaoTotalKwh;
        somaInjetadaHistorico +=
            l.energiaInjetadaKwh + (l.creditosRecebidosDeTerceiros ?? 0.0);

        double autoconsumo = (l.geracaoTotalKwh - l.energiaInjetadaKwh).clamp(
          0,
          double.infinity,
        );
        double consumoTotalReal = autoconsumo + consumoMesTotal;

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
            (consumoMesTotal * tarifaInteligente) +
            l.custoDemandaR +
            (l.custoIluminacaoPublica ?? 0.0) +
            (l.multaReativo ?? 0.0);
        somaEconomiaReais += (custoSemSolar - l.valorFaturaR).clamp(
          0,
          double.infinity,
        );
      }

      double consumoAbativel = consumoMesTotal > custoDisponibilidade
          ? consumoMesTotal - custoDisponibilidade
          : 0.0;

      double aConsumir = consumoAbativel;
      while (aConsumir > 0 && lotes.isNotEmpty) {
        final lote = lotes.first;
        if (lote.kwh <= aConsumir) {
          aConsumir -= lote.kwh;
          lotes.removeAt(0);
        } else {
          lote.kwh -= aConsumir;
          aConsumir = 0;
        }
      }
      if (entradaCreditoMesParaSaldo > 0) {
        lotes.add(
          _LoteCredito(
            mesAbsoluto: mesAtualAbsoluto,
            kwh: entradaCreditoMesParaSaldo,
          ),
        );
      }

      saldoRollingKwh = lotes.fold(0.0, (s, lote) => s + lote.kwh);

      // CORREÇÃO DO LINTER: Inserido chaves
      if (saldoRollingKwh < 0) {
        saldoRollingKwh = 0;
      }

      if (l.saldoInformadoNaFatura != null) {
        double diferenca = saldoRollingKwh - l.saldoInformadoNaFatura!;
        if (diferenca > _kSaldoMinimoRelevante) {
          somaDesviosConcessionaria += diferenca;
        }
        if (l.saldoInformadoNaFatura! > 0) {
          lotes.clear();
          lotes.add(
            _LoteCredito(
              mesAbsoluto: mesAtualAbsoluto,
              kwh: l.saldoInformadoNaFatura!,
            ),
          );
          saldoRollingKwh = l.saldoInformadoNaFatura!;
        } else {
          lotes.clear();
          saldoRollingKwh = 0;
        }
      }
    }

    double mediaGer = 0;
    double mediaCons = 0;
    if (historicoOrdenado.isNotEmpty) {
      var recentes = historicoOrdenado.length > 3
          ? historicoOrdenado.sublist(historicoOrdenado.length - 3)
          : historicoOrdenado;
      mediaGer =
          recentes.fold(0.0, (prev, e) => prev + e.geracaoTotalKwh) /
          recentes.length;
      mediaCons =
          recentes.fold(0.0, (prev, e) => prev + _obterConsumoTotal(e)) /
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

  static double calcularDesvioDoMes(
    Usina usina,
    LancamentoMensal atual,
    LancamentoMensal? anterior,
  ) {
    if (atual.saldoInformadoNaFatura == null) return 0.0;
    if (anterior == null || anterior.saldoInformadoNaFatura == null) return 0.0;

    double recebido = _calcularCreditoRecebidoLiquido(usina, atual);
    double taxaMinima = _obterCustoDisponibilidade(usina);
    double consumoTotal = _obterConsumoTotal(atual);

    double consumoAbativel = consumoTotal > taxaMinima
        ? consumoTotal - taxaMinima
        : 0.0;

    double saldoMensalGerado = recebido - consumoAbativel;
    double saldoEsperado = anterior.saldoInformadoNaFatura! + saldoMensalGerado;

    // CORREÇÃO DO LINTER: Inserido chaves
    if (saldoEsperado < 0) {
      saldoEsperado = 0;
    }

    double desvio = saldoEsperado - atual.saldoInformadoNaFatura!;
    return desvio > _kSaldoMinimoRelevante ? desvio : 0.0;
  }

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
      } catch (e) {
        debugPrint('[V3.4] Usina filha não encontrada: $e');
      }

      double custoDispFilha = usinaFilha != null
          ? _obterCustoDisponibilidade(usinaFilha)
          : 100.0;
      double consumoFilhaTotal = _obterConsumoTotal(lancamentoFilha);

      double consumoAbativelFilha = consumoFilhaTotal > custoDispFilha
          ? consumoFilhaTotal - custoDispFilha
          : 0.0;

      relatorio.add(
        BalancoItem(
          nome: vinculo.nome,
          tipo: 'BENEFICIARIA',
          percentual: vinculo.percentual,
          creditoRecebido: creditoDireito,
          consumoReal: consumoFilhaTotal,
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
      double creditoGeradoraTotal =
          lancamentoGeradora.energiaInjetadaKwh - energiaEnviadaParaFilhas;

      double custoDispGeradora = _obterCustoDisponibilidade(geradora);
      double consumoGeradoraTotal = _obterConsumoTotal(lancamentoGeradora);

      double consumoAbativelGeradora = consumoGeradoraTotal > custoDispGeradora
          ? consumoGeradoraTotal - custoDispGeradora
          : 0.0;

      relatorio.insert(
        0,
        BalancoItem(
          nome: "${geradora.nome} (Própria)",
          tipo: 'GERADORA',
          percentual: percGeradora,
          creditoRecebido: creditoGeradoraTotal,
          consumoReal: consumoGeradoraTotal,
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

  static List<Map<String, dynamic>> gerarAlertasDeGestao(
    Usina usina,
    LancamentoMensal? ultimo,
    double saldoCreditosGlobal,
  ) {
    List<Map<String, dynamic>> alertas = [];
    if (ultimo == null) return alertas;

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

    final resumo = gerarResumoMesOficial(usina, ultimo);

    if (resumo.sobraFisicaDoMes < 0) {
      double deficit = resumo.sobraFisicaDoMes.abs();
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

    final double divergenciaAneel = auditarAneelContraFatura(usina, ultimo);
    if (divergenciaAneel > 0) {
      alertas.add({
        'tipo': 'concessionaria_fora_aneel',
        'titulo': 'Distribuidora fora da Regra ANEEL em ${usina.nome}',
        'mensagem':
            'O saldo informado na sua fatura diverge em ${divergenciaAneel.toStringAsFixed(0)} kWh do que a regra ANEEL prevê para a unidade ${usina.nome}. Verifique se a distribuidora aplicou corretamente o abatimento da taxa de disponibilidade e conteste caso necessário.',
        'cor': 'red',
        'icone': 'gavel',
      });
    }

    LancamentoMensal? anterior = historico.length >= 2 ? historico[1] : null;
    double desvioDaConcessionaria = calcularDesvioDoMes(
      usina,
      ultimo,
      anterior,
    );

    if (desvioDaConcessionaria > 0) {
      alertas.add({
        'tipo': 'creditos_desviados',
        'titulo': 'Créditos não lançados para ${usina.nome}!',
        'mensagem':
            'A concessionária deixou de creditar  ${desvioDaConcessionaria.toStringAsFixed(0)} kWh no seu banco de créditos para a unidade ${usina.nome}. Verifique e conteste a sua fatura!',
        'cor': 'red',
        'icone': 'policy',
      });
    }

    if (!usina.isGeradora) {
      double recebidoReal =
          (ultimo.creditosRecebidosDeTerceiros != null &&
              ultimo.creditosRecebidosDeTerceiros! > 0)
          ? ultimo.creditosRecebidosDeTerceiros!
          : ultimo.energiaInjetadaKwh;

      double totalTeorico = 0;
      List<String> nomesDasMaes = [];

      final boxUsinas = Hive.box<Usina>('usinas');
      final maes = boxUsinas.values.where((u) => u.isGeradora && !u.isDeletado);

      int mesBuscaMae = ultimo.dataReferencia.month - 1;
      int anoBuscaMae = ultimo.dataReferencia.year;

      if (mesBuscaMae == 0) {
        mesBuscaMae = 12;
        anoBuscaMae -= 1;
      }

      for (var mae in maes) {
        try {
          var lancMae = boxLanc.values.firstWhere(
            (l) =>
                l.usinaId == mae.id &&
                l.dataReferencia.year == anoBuscaMae &&
                l.dataReferencia.month == mesBuscaMae &&
                !l.isDeletado,
          );

          double enviadoPorEstaMae = obterCreditoRepassadoParaFilha(
            mae,
            lancMae,
            usina.id,
          );

          if (enviadoPorEstaMae > 0) {
            totalTeorico += enviadoPorEstaMae;
            if (!nomesDasMaes.contains(mae.nome)) {
              nomesDasMaes.add(mae.nome);
            }
          }
        } catch (e) {
          debugPrint('[V3.4] Falha ao auditar repasse: $e');
        }
      }

      double diferencaRepasse = totalTeorico - recebidoReal;

      if (diferencaRepasse > 1.0) {
        String textoMaes = nomesDasMaes.isNotEmpty
            ? nomesDasMaes.join(', ')
            : 'usina mãe';

        double cotaTaxaMinima = calcularCotaTaxaMinimaFilha(
          usina,
          ultimo.dataReferencia,
        );

        String mensagem;
        if (cotaTaxaMinima > 0.5) {
          mensagem =
              'A usina mãe ($textoMaes) só pôde repassar '
              '${recebidoReal.toStringAsFixed(1)} kWh para ${usina.nome} neste ciclo. '
              'Pela regra ANEEL, deveria ter repassado '
              '${totalTeorico.toStringAsFixed(1)} kWh.\n\n'
              'Os ${diferencaRepasse.toStringAsFixed(0)} kWh faltantes correspondem à fatia desta unidade '
              'sobre a taxa mínima que a distribuidora retirou indevidamente da mãe.\n\n'
              'Não houve perda no trânsito — houve retenção na origem. '
              'Veja o alerta "Distribuidora Fora da ANEEL" na tela da usina $textoMaes.';
        } else {
          mensagem =
              'A usina mãe ($textoMaes) enviou ${totalTeorico.toStringAsFixed(1)} kWh '
              'no ciclo passado, mas a concessionária só creditou '
              '${recebidoReal.toStringAsFixed(1)} kWh na unidade ${usina.nome} '
              'neste mês. Ocorreu uma retenção indevida na transferência.';
        }

        alertas.add({
          'tipo': 'fraude_repasse',
          'titulo': 'Retenção no Repasse (Origem: Usina Mãe)',
          'mensagem': mensagem,
          'cor': 'red',
          'icone': 'compare_arrows',
        });
      }
    }

    return alertas;
  }

  static Map<String, dynamic> calcularSaudeSistema(
    Usina usina,
    List<LancamentoMensal> lancamentos,
  ) {
    if (!usina.isGeradora || lancamentos.isEmpty) {
      return {'eficiencia': 100.0, 'anos': 0.0};
    }

    double potenciaEfetivaInstalada = calcularPotenciaEfetiva(usina);

    final ordenados = List<LancamentoMensal>.from(lancamentos)
      ..sort((a, b) => a.dataReferencia.compareTo(b.dataReferencia));
    double anosDeUso =
        DateTime.now().difference(ordenados.first.dataReferencia).inDays /
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

  static double obterTotalDistribuidoNoMes(
    Usina geradora,
    LancamentoMensal lancamentoMae,
  ) {
    if (!geradora.isGeradora || geradora.beneficiarias.isEmpty) return 0.0;

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
    if (!geradora.isGeradora) return 0.0;
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
      debugPrint('[V3.4] Falha ao obter crédito repassado: $e');
      return 0.0;
    }
  }

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

        final resumo = gerarResumoMesOficial(filha, ultimoLancamento);

        if (resumo.sobraFisicaDoMes < 0) {
          double deficitDoMes = resumo.sobraFisicaDoMes.abs();

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
                      'A unidade ${filha.nome} consumiu reservas (ou pagou conta) este mês, enquanto a usina ${mae.nome} tem saldo sobrando.\nRecomendação: Aumente o % de rateio para a ${filha.nome}!',
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

  // ===========================================================================
  // MÉTODOS NOVOS (MOTOR CENTRALIZADO PARA REFACTORING FUTURO DAS TELAS)
  // ===========================================================================

  static ProcessamentoCiclo analisarCiclo(
    Usina usina,
    LancamentoMensal atual, {
    LancamentoMensal? anterior,
  }) {
    double tarifa = resolverTarifaAplicavel(atual);
    double taxaMin = _obterCustoDisponibilidade(usina);
    double geracao = usina.isGeradora ? atual.geracaoTotalKwh : 0.0;
    double injetadoReal = atual.energiaInjetadaKwh;
    double consumoRedeTotal = _obterConsumoTotal(atual);
    double recebidoTerceiros = atual.creditosRecebidosDeTerceiros ?? 0.0;

    double autoconsumo = usina.isGeradora
        ? (geracao - injetadoReal).clamp(0.0, double.infinity)
        : 0.0;
    double consumoRealLocal = autoconsumo + consumoRedeTotal;

    double taxaMinimaRetida = consumoRedeTotal < taxaMin
        ? consumoRedeTotal
        : taxaMin;
    double consumoAbativel = consumoRedeTotal > taxaMin
        ? consumoRedeTotal - taxaMin
        : 0.0;

    double totalCreditosDisponiveisNoMes = injetadoReal + recebidoTerceiros;

    double enviadoParaFilhas = 0.0;
    if (usina.isGeradora) {
      var vigentes = _obterBeneficiariasVigentes(usina, atual.dataReferencia);
      double percentualEnviado = vigentes.fold(
        0.0,
        (sum, b) => sum + b.percentual,
      );
      double excedente = _calcularExcedenteParaRateio(usina, atual);
      enviadoParaFilhas = excedente * (percentualEnviado / 100);
    }

    double creditoLiquidoLocal =
        totalCreditosDisponiveisNoMes - enviadoParaFilhas;
    double sobraFisicaDoMes = creditoLiquidoLocal - consumoAbativel;

    double economiaAutoconsumo = autoconsumo * tarifa;
    double energiaCompensada = creditoLiquidoLocal.clamp(0.0, consumoAbativel);
    double economiaCompensada =
        energiaCompensada * (tarifa * _kFatorRendimentoGD2);
    double economiaTotal = economiaAutoconsumo + economiaCompensada;

    double saldoExibicao = atual.saldoInformadoNaFatura ?? 0.0;
    bool isEstimado = false;

    if (saldoExibicao == 0.0 &&
        anterior != null &&
        anterior.saldoInformadoNaFatura != null) {
      saldoExibicao = (anterior.saldoInformadoNaFatura! + sobraFisicaDoMes)
          .clamp(0.0, double.infinity);
      isEstimado = true;
    } else if (saldoExibicao == 0.0) {
      saldoExibicao = sobraFisicaDoMes > 0 ? sobraFisicaDoMes : 0.0;
      isEstimado = true;
    }

    List<Map<String, dynamic>> listaAlertas = _gerarAlertasInternos(
      usina,
      atual,
      anterior,
      sobraFisicaDoMes,
      recebidoTerceiros,
    );

    return ProcessamentoCiclo(
      geracaoTotal: geracao,
      consumoTotal: consumoRedeTotal,
      injetadoNaRede: injetadoReal,
      recebidoDeTerceiros: recebidoTerceiros,
      autoconsumo: autoconsumo,
      consumoRealLocal: consumoRealLocal,
      consumoAbativel: consumoAbativel,
      taxaMinimaRetida: taxaMinimaRetida,
      totalCreditosDisponiveisNoMes: totalCreditosDisponiveisNoMes,
      sobraFisicaDoMes: sobraFisicaDoMes,
      saldoAcumuladoExibicao: saldoExibicao,
      isSaldoEstimado: isEstimado,
      tarifaAplicada: tarifa,
      economiaAutoconsumo: economiaAutoconsumo,
      economiaCompensada: economiaCompensada,
      economiaTotalReais: economiaTotal,
      alertas: listaAlertas,
    );
  }

  static List<Map<String, dynamic>> _gerarAlertasInternos(
    Usina usina,
    LancamentoMensal atual,
    LancamentoMensal? anterior,
    double sobraFisicaDoMes,
    double recebidoTerceiros,
  ) {
    List<Map<String, dynamic>> alertas = [];

    if ((atual.multaReativo ?? 0) > 0) {
      alertas.add({
        'tipo': 'fuga_dinheiro',
        'titulo': 'Fuga de Dinheiro (Multa)!',
        'mensagem':
            'A unidade pagou R\$ ${atual.multaReativo!.toStringAsFixed(2)} de multa por Energia Reativa.',
        'cor': 'red',
        'icone': 'bolt',
      });
    }

    double custosFixos =
        atual.custoDemandaR + (atual.custoIluminacaoPublica ?? 0);
    if (atual.valorFaturaR > 0 && (custosFixos / atual.valorFaturaR) > 0.6) {
      alertas.add({
        'tipo': 'custo_fixo_alto',
        'titulo': 'Custos Fixos Elevados',
        'mensagem':
            'Mais de 60% da fatura é composta por Demanda ou Taxas. A energia solar não abate estes custos.',
        'cor': 'orange',
        'icone': 'domain',
      });
    }

    if (sobraFisicaDoMes < 0) {
      double deficit = sobraFisicaDoMes.abs();
      double saldoMesAnterior = anterior?.saldoInformadoNaFatura ?? 0.0;

      if (saldoMesAnterior >= deficit) {
        alertas.add({
          'tipo': 'consumo_reserva',
          'titulo': 'Consumindo Reserva',
          'mensagem':
              'O sistema utilizou ${deficit.toStringAsFixed(0)} kWh do seu Banco de Créditos para cobrir o mês.',
          'cor': 'orange',
          'icone': 'hourglass_bottom',
        });
      } else if (saldoMesAnterior > 1.0) {
        double faltou = deficit - saldoMesAnterior;
        alertas.add({
          'tipo': 'deficit_parcial',
          'titulo': 'Reserva Insuficiente',
          'mensagem':
              'A reserva só tinha ${saldoMesAnterior.toStringAsFixed(0)} kWh. A diferença de ${faltou.toStringAsFixed(0)} kWh foi cobrada em Reais.',
          'cor': 'red',
          'icone': 'monetization_on',
        });
      } else {
        alertas.add({
          'tipo': 'deficit_real',
          'titulo': 'Fatura Descoberta (Pagamento Extra)',
          'mensagem':
              'Faltaram ${deficit.toStringAsFixed(0)} kWh para abater o consumo. A diferença foi cobrada em Reais.',
          'cor': 'red',
          'icone': 'monetization_on',
        });
      }
    }

    final double divergenciaAneel = auditarAneelContraFatura(usina, atual);
    if (divergenciaAneel > 0) {
      alertas.add({
        'tipo': 'concessionaria_fora_aneel',
        'titulo': 'Distribuidora fora da Regra ANEEL',
        'mensagem':
            'A distribuidora desviou ${divergenciaAneel.toStringAsFixed(0)} kWh do seu direito neste mês. Verifique se a taxa de disponibilidade foi aplicada corretamente.',
        'cor': 'red',
        'icone': 'gavel',
      });
    }

    double totalTeorico = 0;
    List<String> nomesDasMaes = [];
    final boxUsinas = Hive.box<Usina>('usinas');
    final boxLanc = Hive.box<LancamentoMensal>('lancamentos');

    final maesQueMeEnviam = boxUsinas.values.where(
      (u) =>
          u.isGeradora &&
          !u.isDeletado &&
          u.beneficiarias.any((b) => b.idUsinaFilha == usina.id),
    );

    int mesBusca = atual.dataReferencia.month - 1;
    int anoBusca = atual.dataReferencia.year;
    if (mesBusca == 0) {
      mesBusca = 12;
      anoBusca -= 1;
    }

    for (var mae in maesQueMeEnviam) {
      try {
        var lancMae = boxLanc.values.firstWhere(
          (l) =>
              l.usinaId == mae.id &&
              l.dataReferencia.year == anoBusca &&
              l.dataReferencia.month == mesBusca &&
              !l.isDeletado,
        );
        double enviado = obterCreditoRepassadoParaFilha(mae, lancMae, usina.id);
        if (enviado > 0) {
          totalTeorico += enviado;
          nomesDasMaes.add(mae.nome);
        }
      } catch (_) {}
    }

    double diferencaRepasse = totalTeorico - recebidoTerceiros;
    if (diferencaRepasse > 1.0) {
      String textoMaes = nomesDasMaes.isNotEmpty
          ? nomesDasMaes.join(', ')
          : 'usina mãe';
      alertas.add({
        'tipo': 'fraude_repasse',
        'titulo': 'Retenção no Repasse (Mãe vs Filha)',
        'mensagem':
            'A usina $textoMaes enviou ${totalTeorico.toStringAsFixed(0)} kWh, mas a concessionária creditou apenas ${recebidoTerceiros.toStringAsFixed(0)} kWh na fatura atual. Desvio de ${diferencaRepasse.toStringAsFixed(0)} kWh.',
        'cor': 'red',
        'icone': 'compare_arrows',
      });
    }

    return alertas;
  }
}

// ===========================================================================
// ESTRUTURA INTERNA — fila FIFO de créditos
// ===========================================================================
class _LoteCredito {
  final int mesAbsoluto;
  double kwh;

  _LoteCredito({required this.mesAbsoluto, required this.kwh});
}
