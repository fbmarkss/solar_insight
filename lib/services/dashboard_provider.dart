// Caminho: lib/services/dashboard_provider.dart
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
  double totalEconomizado = 0; // Soma de TODAS as usinas (para o Card Verde)
  double saldoCreditosTotal = 0;
  double totalEnergiaDistribuida = 0;

  // --- DADOS ESPECÍFICOS PARA O CÁLCULO DE ROI (FILTRADOS) ---
  double _economiaConsideradaROI = 0;
  double _investimentoConsideradoROI = 0;
  int _usinasSemInvestimentoCount = 0;

  // Getters para o ROI ponderado
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

  /// Método para disparar a sincronização manual e atualizar a interface
  Future<String> sincronizarDados() async {
    _isLoading = true;
    notifyListeners();

    try {
      // 1. Executa a Sincronização e a Faxina Inteligente
      final resultado = await SincronizacaoService().sincronizarTudo();

      // 2. Recarrega os dados locais (Hive) para refletir a limpeza/novos dados
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

    // Garantir que as boxes estão abertas e prontas
    final boxUsinas = Hive.box<Usina>('usinas');
    final boxLancamentos = Hive.box<LancamentoMensal>('lancamentos');

    // 1. Filtrar apenas usinas ativas e NÃO deletadas
    _listaUsinas = boxUsinas.values
        .where((u) => u.ativa && !u.isDeletado)
        .toList();

    List<Usina> usinasParaCalcular;
    if (_usinaSelecionada != null) {
      // Se a usina selecionada sumiu ou foi deletada, volta para "Todas"
      if (_usinaSelecionada!.isDeletado || !_usinaSelecionada!.ativa) {
        _usinaSelecionada = null;
        usinasParaCalcular = _listaUsinas;
      } else {
        usinasParaCalcular = [_usinaSelecionada!];
      }
    } else {
      usinasParaCalcular = _listaUsinas;
    }

    // Variáveis Gerais
    double somaGeracaoTotal = 0;
    double somaEconomiaTotal = 0;
    double somaSaldo = 0;
    double somaDistribuidaReal = 0;
    double somaPotenciaNominal = 0;
    double somaEficienciaPonderada = 0;

    // Variáveis Específicas para ROI Ponderado
    double tempInvestimentoROI = 0;
    double tempEconomiaROI = 0;
    int tempCountSemInvestimento = 0;

    int contUsinas = 0;
    DateTime? dataMaisRecente;
    List<Map<String, dynamic>> listaAlertasTemp = [];

    // --- LOOP DE CÁLCULOS VITALÍCIOS ---
    for (var usina in usinasParaCalcular) {
      contUsinas++;

      // Filtra apenas lançamentos válidos da usina
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

      // Chama a Calculadora 2.0 (Motor Central)
      final metricas = CalculadoraEnergetica.calcularMetricasGerais(
        usina,
        lancamentosUsina,
      );

      // Acumula Totais Gerais (Para Cards de Economia e Geração)
      somaGeracaoTotal += metricas.totalGeradoKwh;
      somaEconomiaTotal += metricas.valorTotalEconomizadoR; // Soma TUDO
      somaSaldo += metricas.saldoCreditosEstimado;

      // --- LÓGICA DE ROI PONDERADO ---
      // Só somamos para o cálculo do ROI se a usina tiver investimento cadastrado (> 0)
      if (usina.totalInvestido > 0) {
        tempInvestimentoROI += usina.totalInvestido;
        tempEconomiaROI += metricas.valorTotalEconomizadoR;
      } else {
        // Ignora Beneficiárias no contador de erro do ROI
        if (usina.isGeradora) {
          tempCountSemInvestimento++;
        }
      }
      // -------------------------------

      if (usina.isGeradora) {
        somaPotenciaNominal += usina.potenciaTotalPaineisKwp;

        // Soma da Distribuição Real
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

    // Média de eficiência global ponderada pela potência
    eficienciaGlobalMedia = somaPotenciaNominal > 0
        ? (somaEficienciaPonderada / somaPotenciaNominal)
        : 100.0;

    // --- LOOP DE CÁLCULO MENSAL E ALERTAS ---
    double somaGeracaoMes = 0;
    double somaConsumoMes = 0;
    String nomeMes = "Sem dados";

    if (dataMaisRecente != null) {
      nomeMes = DateFormat(
        "MMMM yyyy",
        "pt_BR",
      ).format(dataMaisRecente).toUpperCase();

      for (var usina in usinasParaCalcular) {
        var lancamentoMes = boxLancamentos.values.firstWhere(
          (l) =>
              l.usinaId == usina.id &&
              !l.isDeletado &&
              l.dataReferencia.year == dataMaisRecente!.year &&
              l.dataReferencia.month == dataMaisRecente.month,
          orElse: () => LancamentoMensal(
            usinaId: usina.id,
            dataReferencia: dataMaisRecente!,
            geracaoTotalKwh: 0,
            energiaInjetadaKwh: 0,
            energiaConsumidaRedeKwh: 0,
            tarifaKwh: 0,
            valorFaturaR: 0,
          ),
        );

        if (lancamentoMes.usinaId.isNotEmpty) {
          // =========================================================
          // A MÁGICA ACONTECE AQUI: Chamamos a Fonte Única de Verdade
          // =========================================================
          final resumo = CalculadoraEnergetica.gerarResumoMesOficial(
            usina,
            lancamentoMes,
          );

          if (_usinaSelecionada == null) {
            // Se for Visão Global: Soma a produção pura e o consumo total
            somaGeracaoMes += resumo.geracaoTotal;
            somaConsumoMes += resumo.consumoRealLocal;
          } else {
            // Se for Visão Individual (Aba específica da usina):
            // Mostra a Geração se for mãe, ou o que Recebeu se for filha
            somaGeracaoMes += usina.isGeradora
                ? resumo.geracaoTotal
                : resumo.injetadoOuRecebido;
            somaConsumoMes += resumo.consumoRealLocal;
          }

          var novosAlertas = CalculadoraEnergetica.gerarAlertasDeGestao(
            usina,
            lancamentoMes,
            somaSaldo,
          );
          listaAlertasTemp.addAll(novosAlertas);
        }
      }
    }

    // Atribuição final dos dados
    totalGerado = somaGeracaoTotal;
    totalEconomizado = somaEconomiaTotal;
    saldoCreditosTotal = somaSaldo;
    totalEnergiaDistribuida = somaDistribuidaReal;
    potenciaInstaladaNominal = somaPotenciaNominal;
    totalUsinas = contUsinas;
    geracaoMensal = somaGeracaoMes;
    consumoMensalReal = somaConsumoMes;
    nomeMesReferencia = nomeMes;
    alertasDoSistema = listaAlertasTemp;

    // Atribuição ROI Ponderado
    _investimentoConsideradoROI = tempInvestimentoROI;
    _economiaConsideradaROI = tempEconomiaROI;
    _usinasSemInvestimentoCount = tempCountSemInvestimento;

    _isLoading = false;
    notifyListeners();
  }
}
