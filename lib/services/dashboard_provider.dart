// Caminho: lib/services/dashboard_provider.dart
// Descrição: Provider de estado do Dashboard. Agrega métricas de todas as usinas.
// Versão: V4.0 — INTEGRAÇÃO COM MOTOR CENTRAL (DTO ProcessamentoCiclo)
// - ATUALIZADO: Agora utiliza o ProcessamentoCiclo para obter dados do mês e alertas.
// - ATUALIZADO: Remoção do loop duplo (refsParaAlertas). Tudo resolvido em 1 passo.
// - MANTIDO: Todos os getters e estruturas públicas (não quebra a tela).

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../models/usina.dart';
import '../models/lancamento.dart';
import '../utils/calculadora_energetica.dart';
import '../services/sincronizacao_service.dart';

class DashboardProvider extends ChangeNotifier {
  // --- TOTAIS VITALÍCIOS (GERAIS) ---
  double totalGerado = 0;
  double totalEconomizado = 0;
  double saldoCreditosTotal = 0;
  double totalEnergiaDistribuida = 0;

  // --- DADOS ESPECÍFICOS PARA O CÁLCULO DE ROI (FILTRADOS) ---
  double _economiaConsideradaROI = 0;
  double _investimentoConsideradoROI = 0;
  int _usinasSemInvestimentoCount = 0;

  double get economiaConsideradaROI => _economiaConsideradaROI;
  double get investimentoConsideradoROI => _investimentoConsideradoROI;
  int get usinasSemInvestimentoCount => _usinasSemInvestimentoCount;

  // --- POTÊNCIA E SAÚDE ---
  double potenciaInstaladaNominal = 0;
  double eficienciaGlobalMedia = 100;
  int totalUsinas = 0;

  // --- TOTAIS DO ÚLTIMO MÊS ---
  double geracaoMensal = 0;
  double consumoMensalReal = 0;
  String nomeMesReferencia = "---";

  // --- ALERTAS ---
  List<Map<String, dynamic>> alertasDoSistema = [];

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  List<Usina> _listaUsinas = [];
  Usina? _usinaSelecionada;

  Usina? get usinaSelecionada => _usinaSelecionada;

  DashboardProvider() {
    _carregarDados();
  }

  // ===========================================================================
  // RESET (para uso no logout — limpa tudo sem depender do Hive)
  // ===========================================================================
  void reset() {
    totalGerado = 0;
    totalEconomizado = 0;
    saldoCreditosTotal = 0;
    totalEnergiaDistribuida = 0;

    _economiaConsideradaROI = 0;
    _investimentoConsideradoROI = 0;
    _usinasSemInvestimentoCount = 0;

    potenciaInstaladaNominal = 0;
    eficienciaGlobalMedia = 100;
    totalUsinas = 0;

    geracaoMensal = 0;
    consumoMensalReal = 0;
    nomeMesReferencia = "---";

    alertasDoSistema = [];
    _listaUsinas = [];
    _usinaSelecionada = null;

    _isLoading = true;
    notifyListeners();
  }

  Future<String> sincronizarDados() async {
    _isLoading = true;
    notifyListeners();

    try {
      final resultado = await SincronizacaoService().sincronizarTudo();
      await _carregarDados();
      return resultado;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return "Erro ao sincronizar: $e";
    }
  }

  List<Usina> getTodasUsinas() => _listaUsinas;

  void selecionarUsina(Usina? usina) {
    _usinaSelecionada = usina;
    _carregarDados();
  }

  void atualizar() {
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    _isLoading = true;

    if (!Hive.isBoxOpen('usinas') || !Hive.isBoxOpen('lancamentos')) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    final boxUsinas = Hive.box<Usina>('usinas');
    final boxLancamentos = Hive.box<LancamentoMensal>('lancamentos');

    _listaUsinas = boxUsinas.values
        .where((u) => u.ativa && !u.isDeletado)
        .toList();

    List<Usina> usinasParaCalcular;
    if (_usinaSelecionada != null) {
      if (_usinaSelecionada!.isDeletado || !_usinaSelecionada!.ativa) {
        _usinaSelecionada = null;
        usinasParaCalcular = _listaUsinas;
      } else {
        usinasParaCalcular = [_usinaSelecionada!];
      }
    } else {
      usinasParaCalcular = _listaUsinas;
    }

    double somaGeracaoTotal = 0;
    double somaEconomiaTotal = 0;
    double somaSaldo = 0;
    double somaDistribuidaReal = 0;
    double somaPotenciaNominal = 0;
    double somaEficienciaPonderada = 0;

    double tempInvestimentoROI = 0;
    double tempEconomiaROI = 0;
    int tempCountSemInvestimento = 0;

    int contUsinas = 0;
    DateTime? dataMaisRecente;

    // Lista unificada para guardar todos os alertas encontrados no mês atual
    List<Map<String, dynamic>> alertasFinais = [];

    for (var usina in usinasParaCalcular) {
      contUsinas++;

      final lancamentosUsina = boxLancamentos.values
          .where((l) => l.usinaId == usina.id && !l.isDeletado)
          .toList();

      if (lancamentosUsina.isNotEmpty) {
        lancamentosUsina.sort(
          (a, b) => b.dataReferencia.compareTo(a.dataReferencia),
        );
        DateTime ultimaDestaUsina = lancamentosUsina.first.dataReferencia;

        if (dataMaisRecente == null ||
            ultimaDestaUsina.isAfter(dataMaisRecente)) {
          dataMaisRecente = ultimaDestaUsina;
        }
      }

      // Calcula as métricas vitais da usina (já usando a matemática GD II por baixo dos panos)
      final metricas = CalculadoraEnergetica.calcularMetricasGerais(
        usina,
        lancamentosUsina,
      );

      somaGeracaoTotal += metricas.totalGeradoKwh;
      somaEconomiaTotal += metricas.valorTotalEconomizadoR;
      somaSaldo += metricas.saldoCreditosEstimado;

      if (usina.totalInvestido > 0) {
        tempInvestimentoROI += usina.totalInvestido;
        tempEconomiaROI += metricas.valorTotalEconomizadoR;
      } else {
        if (usina.isGeradora) {
          tempCountSemInvestimento++;
        }
      }

      if (usina.isGeradora) {
        somaPotenciaNominal += usina.potenciaTotalPaineisKwp;

        if (usina.beneficiarias.isNotEmpty) {
          for (var lancamento in lancamentosUsina) {
            somaDistribuidaReal +=
                CalculadoraEnergetica.obterTotalDistribuidoNoMes(
                  usina,
                  lancamento,
                );
          }
        }

        final saude = CalculadoraEnergetica.calcularSaudeSistema(
          usina,
          lancamentosUsina,
        );
        somaEficienciaPonderada +=
            (saude['eficiencia'] * usina.potenciaTotalPaineisKwp);
      }
    }

    eficienciaGlobalMedia = somaPotenciaNominal > 0
        ? (somaEficienciaPonderada / somaPotenciaNominal)
        : 100.0;

    double somaGeracaoMes = 0;
    double somaConsumoMes = 0;
    String nomeMes = "Sem dados";

    if (dataMaisRecente != null) {
      nomeMes = DateFormat(
        "MMMM yyyy",
        "pt_BR",
      ).format(dataMaisRecente).toUpperCase();

      for (var usina in usinasParaCalcular) {
        final lancamentosUsina =
            boxLancamentos.values
                .where((l) => l.usinaId == usina.id && !l.isDeletado)
                .toList()
              ..sort((a, b) => b.dataReferencia.compareTo(a.dataReferencia));

        LancamentoMensal? lancamentoMes;
        try {
          lancamentoMes = lancamentosUsina.firstWhere(
            (l) =>
                l.dataReferencia.year == dataMaisRecente!.year &&
                l.dataReferencia.month == dataMaisRecente.month,
          );
        } catch (_) {}

        if (lancamentoMes != null) {
          // Busca o lançamento do mês anterior para cálculo preciso de desvios no motor
          LancamentoMensal? anterior;
          int idx = lancamentosUsina.indexOf(lancamentoMes);
          if (idx >= 0 && idx + 1 < lancamentosUsina.length) {
            anterior = lancamentosUsina[idx + 1];
          }

          // ★ INTEGRAÇÃO COM MOTOR CENTRAL:
          // Pede o "Laudo" (DTO) completo para a calculadora
          final ciclo = CalculadoraEnergetica.analisarCiclo(
            usina,
            lancamentoMes,
            anterior: anterior,
          );

          if (_usinaSelecionada == null) {
            somaGeracaoMes += ciclo.geracaoTotal;
            somaConsumoMes += ciclo.consumoRealLocal;
          } else {
            somaGeracaoMes += usina.isGeradora
                ? ciclo.geracaoTotal
                : ciclo.totalCreditosDisponiveisNoMes;
            somaConsumoMes += ciclo.consumoRealLocal;
          }

          // ★ COLETA DE ALERTAS DIRETA DO DTO (Sem loops adicionais!)
          alertasFinais.addAll(ciclo.alertas);
        }
      }
    }

    totalGerado = somaGeracaoTotal;
    totalEconomizado = somaEconomiaTotal;
    saldoCreditosTotal = somaSaldo;
    totalEnergiaDistribuida = somaDistribuidaReal;
    potenciaInstaladaNominal = somaPotenciaNominal;
    totalUsinas = contUsinas;
    geracaoMensal = somaGeracaoMes;
    consumoMensalReal = somaConsumoMes;
    nomeMesReferencia = nomeMes;

    alertasDoSistema = alertasFinais;

    _investimentoConsideradoROI = tempInvestimentoROI;
    _economiaConsideradaROI = tempEconomiaROI;
    _usinasSemInvestimentoCount = tempCountSemInvestimento;

    _isLoading = false;
    notifyListeners();
  }
}
