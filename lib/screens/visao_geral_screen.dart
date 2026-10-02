// Caminho: lib/screens/visao_geral_screen.dart
// Descrição: Dashboard Híbrido com Navegador Aninhado, Clima Real, Gráfico e Alertas.
// Versão: V4.1 — ALINHADO AO MOTOR DTO COM MÊS DINÂMICO NOS ALERTAS.
// - ADICIONADO: O nome do mês de referência agora aparece no título das Notificações.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:hive_flutter/hive_flutter.dart';

import '../services/dashboard_provider.dart';
import '../models/usina.dart';
import '../models/lancamento.dart';
import '../services/sincronizacao_service.dart';
import '../services/clima_service.dart';
import '../utils/app_feedback.dart';
import '../utils/calculadora_energetica.dart';
import 'lancamento_mensal_screen.dart';

class VisaoGeralScreen extends StatefulWidget {
  const VisaoGeralScreen({super.key});

  @override
  State<VisaoGeralScreen> createState() => _VisaoGeralScreenState();
}

class _VisaoGeralScreenState extends State<VisaoGeralScreen> {
  final moedaFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final numeroFormat = NumberFormat.decimalPattern('pt_BR');

  final GlobalKey<NavigatorState> _nestedNavKey = GlobalKey<NavigatorState>();

  Map<String, dynamic> _climaData = {
    'condicao': 'Carregando...',
    'temperatura': '--',
    'icone': Icons.cloud_outlined,
    'cor': Colors.grey,
    'cidade': 'Detectando local...',
    'umidade': '--',
    'sol': '--',
    'previsao_amanha': '',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<DashboardProvider>(context, listen: false).atualizar();
    });

    _buscarClimaReal();
  }

  Future<void> _buscarClimaReal({String? cidade}) async {
    if (!mounted) return;

    setState(() {
      _climaData['condicao'] = 'Buscando...';
      _climaData['temperatura'] = '--';
    });

    final resultado = await ClimaService().buscarClimaReal(
      cidadeManual: cidade,
    );

    if (mounted) {
      setState(() {
        _climaData = resultado;
      });
    }
  }

  void _mostrarBottomSheetSelecionarCidade() {
    final box = Hive.box('sync_metadata');
    String cidadeAtual = box.get('cidade_clima') ?? '';
    String cidadeSelecionada = cidadeAtual;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(Icons.location_city, color: Colors.deepOrange),
                    SizedBox(width: 8),
                    Text(
                      'Buscar Cidade',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Digite a cidade para corrigir a localização. Para voltar ao modo automático (IP), apague o texto e salve.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 16),

                Autocomplete<String>(
                  initialValue: TextEditingValue(text: cidadeAtual),
                  optionsBuilder: (TextEditingValue textEditingValue) async {
                    return await ClimaService().getSugestoesIBGE(
                      textEditingValue.text,
                    );
                  },
                  onSelected: (String selection) {
                    cidadeSelecionada = selection;
                  },
                  fieldViewBuilder:
                      (context, controller, focusNode, onEditingComplete) {
                        controller.addListener(() {
                          cidadeSelecionada = controller.text;
                        });

                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            labelText: 'Nome da cidade',
                            hintText: 'Ex: Colatina',
                            prefixIcon: const Icon(
                              Icons.search,
                              color: Colors.grey,
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(
                                Icons.clear,
                                color: Colors.grey,
                                size: 20,
                              ),
                              onPressed: () {
                                controller.clear();
                                cidadeSelecionada = '';
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Colors.deepOrange,
                                width: 2,
                              ),
                            ),
                          ),
                          onSubmitted: (_) {
                            Navigator.pop(ctx);
                            _buscarClimaReal(cidade: cidadeSelecionada);
                          },
                        );
                      },
                  optionsViewBuilder: (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4.0,
                        borderRadius: BorderRadius.circular(12),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxHeight: 250,
                            maxWidth: 320,
                          ),
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (BuildContext context, int index) {
                              final String option = options.elementAt(index);

                              return InkWell(
                                onTap: () => onSelected(option),
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Colors.grey.shade100,
                                      ),
                                    ),
                                    color: Colors.white,
                                  ),
                                  padding: const EdgeInsets.all(16.0),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.location_on_outlined,
                                        color: Colors.grey,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          option,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w500,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _buscarClimaReal(cidade: cidadeSelecionada);
                    },
                    child: const Text(
                      'ATUALIZAR CLIMA',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
                SizedBox(height: MediaQuery.of(ctx).padding.bottom + 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleRefresh() async {
    Provider.of<DashboardProvider>(context, listen: false).atualizar();
    _buscarClimaReal();

    try {
      final resultado = await SincronizacaoService().sincronizarTudo();
      if (!mounted) return;
      Provider.of<DashboardProvider>(context, listen: false).atualizar();

      if (resultado.contains('Erro') || resultado.contains('Sem internet')) {
        AppFeedback.show(context, resultado, isError: true);
      } else if (resultado == 'Sincronizado.') {
        AppFeedback.show(context, "Tudo já está sincronizado.", isError: false);
      } else {
        AppFeedback.show(
          context,
          "Dados sincronizados com sucesso!",
          isError: false,
        );
      }
    } catch (e) {
      debugPrint('Erro no refresh visual: $e');
    }
  }

  void _abrirLancamento(
    bool isWeb,
    BuildContext localContext, {
    Usina? usina,
    LancamentoMensal? lancamento,
  }) {
    final tela = LancamentoMensalScreen(
      usinaPreSelecionada: usina,
      lancamentoParaEditar: lancamento,
    );

    if (isWeb) {
      _nestedNavKey.currentState!.push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => tela,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } else {
      Navigator.push(localContext, MaterialPageRoute(builder: (_) => tela));
    }
  }

  List<MapEntry<DateTime, double>> _obterDadosGrafico(DashboardProvider dash) {
    final boxLancamentos = Hive.box<LancamentoMensal>('lancamentos');
    var lancamentos = boxLancamentos.values.where((l) => !l.isDeletado);

    if (dash.usinaSelecionada != null) {
      lancamentos = lancamentos.where(
        (l) => l.usinaId == dash.usinaSelecionada!.id,
      );
    }

    Map<DateTime, double> agrupado = {};
    for (var l in lancamentos) {
      DateTime mesAno = DateTime(
        l.dataReferencia.year,
        l.dataReferencia.month,
        1,
      );
      agrupado[mesAno] = (agrupado[mesAno] ?? 0) + l.geracaoTotalKwh;
    }

    var lista = agrupado.entries.toList();
    lista.sort((a, b) => a.key.compareTo(b.key));

    if (lista.length > 6) {
      lista = lista.sublist(lista.length - 6);
    }

    return lista;
  }

  @override
  Widget build(BuildContext context) {
    bool isWeb = MediaQuery.of(context).size.width >= 800;

    if (isWeb) {
      return Navigator(
        key: _nestedNavKey,
        onGenerateRoute: (settings) {
          return MaterialPageRoute(
            builder: (context) => _buildConteudoPrincipal(isWeb, context),
          );
        },
      );
    } else {
      return _buildConteudoPrincipal(isWeb, context);
    }
  }

  Widget _buildConteudoPrincipal(bool isWeb, BuildContext navContext) {
    return Consumer<DashboardProvider>(
      builder: (context, dash, child) {
        if (dash.isLoading) {
          return const Scaffold(
            backgroundColor: Color(0xFFF5F7FA),
            body: Center(
              child: CircularProgressIndicator(color: Colors.deepOrange),
            ),
          );
        }

        double taxaCoberturaMensal = 0;
        if (dash.consumoMensalReal > 0) {
          taxaCoberturaMensal = (dash.geracaoMensal / dash.consumoMensalReal);
        }

        Color corCobertura = Colors.grey;
        String textoCobertura = "Aguardando dados";
        String frasePercentual = "";

        if (dash.consumoMensalReal > 0) {
          int percentual = (taxaCoberturaMensal * 100).toInt();
          frasePercentual = "Você produziu $percentual% do seu consumo total";

          if (taxaCoberturaMensal > 1.05) {
            corCobertura = Colors.green;
            textoCobertura = "Superavit (Sobrou)";
          } else if (taxaCoberturaMensal >= 0.95) {
            corCobertura = Colors.blue;
            textoCobertura = "Equilibrado";
          } else {
            corCobertura = Colors.orange;
            textoCobertura = "Déficit (Faltou)";
          }
        }

        double percentualRoi = 0;
        if (dash.investimentoConsideradoROI > 0) {
          percentualRoi =
              (dash.economiaConsideradaROI / dash.investimentoConsideradoROI) *
              100;
        }

        Widget filtro = _buildFiltro(dash);
        Widget cardAmbiental = _buildEnvironmentalCard(dash.totalGerado);
        Widget cardClima = _buildClimaCard();

        List<Map<String, dynamic>> alertasTotais = List.from(
          dash.alertasDoSistema,
        );

        if (dash.usinaSelecionada == null) {
          alertasTotais.addAll(
            CalculadoraEnergetica.gerarAlertaDeOtimizacaoDeRateio(),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            bool isWidePanel = constraints.maxWidth >= 1000;

            return Scaffold(
              backgroundColor: const Color(0xFFF5F7FA),
              body: isWidePanel
                  ? _buildWebLayout(
                      dash,
                      filtro,
                      cardAmbiental,
                      cardClima,
                      taxaCoberturaMensal,
                      corCobertura,
                      textoCobertura,
                      percentualRoi,
                      navContext,
                      isWeb,
                      alertasTotais,
                    )
                  : _buildMobileLayout(
                      dash,
                      filtro,
                      cardAmbiental,
                      cardClima,
                      taxaCoberturaMensal,
                      corCobertura,
                      textoCobertura,
                      percentualRoi,
                      frasePercentual,
                      navContext,
                      isWeb,
                      alertasTotais,
                    ),
              floatingActionButton: isWidePanel
                  ? null
                  : FloatingActionButton.extended(
                      onPressed: () => _abrirLancamento(
                        isWeb,
                        navContext,
                        usina: dash.usinaSelecionada,
                      ),
                      backgroundColor: const Color.fromARGB(255, 38, 143, 230),
                      foregroundColor: Colors.white,
                      icon: const Icon(Icons.add),
                      label: const Text(
                        'Lançamento',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
            );
          },
        );
      },
    );
  }

  Widget _buildWebLayout(
    DashboardProvider dash,
    Widget filtro,
    Widget cardAmbiental,
    Widget cardClima,
    double taxaCoberturaMensal,
    Color corCobertura,
    String textoCobertura,
    double percentualRoi,
    BuildContext context,
    bool isWeb,
    List<Map<String, dynamic>> alertasCompletos,
  ) {
    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: Colors.deepOrange,
      backgroundColor: Colors.white,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 16,
              runSpacing: 16,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Visão Geral',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey[900],
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      'Acompanhamento energético e financeiro',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.blueGrey[400],
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () => _abrirLancamento(
                          isWeb,
                          context,
                          usina: dash.usinaSelecionada,
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text(
                          'Lançar Mês',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                    SizedBox(width: 250, child: filtro),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 32),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildWaveChartCard(dash),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: _buildModernKpi(
                              'Economia Total',
                              moedaFormat.format(dash.totalEconomizado),
                              Icons.savings_outlined,
                              Colors.green,
                              bgLight: true,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildModernKpi(
                              'ROI Estimado',
                              '${percentualRoi.toStringAsFixed(1)}%',
                              Icons.trending_up,
                              percentualRoi >= 100
                                  ? Colors.blue
                                  : Colors.orange,
                              subtitle: dash.investimentoConsideradoROI > 0
                                  ? 'Retorno'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildModernKpi(
                              'Créditos',
                              '${numeroFormat.format(dash.saldoCreditosTotal)} kWh',
                              Icons.bolt,
                              Colors.amber.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // ★ AQUI: Passamos a string do mês para a seção WEB
                      _buildAlertasSection(
                        alertasCompletos,
                        dash.nomeMesReferencia,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildGaugeCardWeb(
                        dash,
                        taxaCoberturaMensal,
                        corCobertura,
                        textoCobertura,
                      ),
                      const SizedBox(height: 24),
                      _buildTechSummary(dash),
                      const SizedBox(height: 24),
                      cardClima,
                      const SizedBox(height: 24),
                      cardAmbiental,
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout(
    DashboardProvider dash,
    Widget filtro,
    Widget cardAmbiental,
    Widget cardClima,
    double taxaCoberturaMensal,
    Color corCobertura,
    String textoCobertura,
    double percentualRoi,
    String frasePercentual,
    BuildContext context,
    bool isWeb,
    List<Map<String, dynamic>> alertasCompletos,
  ) {
    return RefreshIndicator(
      color: Colors.deepOrange,
      backgroundColor: Colors.white,
      onRefresh: _handleRefresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Visão Geral',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  color: Colors.black87,
                ),
              ),
              Text(
                'Acompanhamento energético e financeiro',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 24),
          filtro,
          const SizedBox(height: 24),
          _buildWaveChartCard(dash, isMobile: true),
          const SizedBox(height: 24),
          _buildCardEconomia(dash),
          const SizedBox(height: 16),
          if (dash.investimentoConsideradoROI > 0)
            _buildCardROI(
              percentualRoi,
              dash.investimentoConsideradoROI,
              dash.economiaConsideradaROI,
              dash.usinasSemInvestimentoCount,
            ),
          const SizedBox(height: 24),
          _buildCardBalanco(
            dash,
            corCobertura,
            textoCobertura,
            taxaCoberturaMensal,
            frasePercentual,
          ),
          const SizedBox(height: 24),
          _buildStatsRow(dash),
          const SizedBox(height: 16),
          cardClima,
          const SizedBox(height: 16),
          cardAmbiental,
          const SizedBox(height: 24),
          if (alertasCompletos.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                // ★ AQUI: Injetamos o nome do mês diretamente no texto da seção MOBILE
                'NOTIFICAÇÕES E ALERTAS (${dash.nomeMesReferencia})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            ...alertasCompletos.map((alerta) => _buildModernAlertCard(alerta)),
          ],
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  // --- RESTO DOS MÉTODOS DE WIDGETS ---

  // ★ AQUI: A função agora recebe o parâmetro do mês dinâmico e o exibe no título
  Widget _buildAlertasSection(
    List<Map<String, dynamic>> alertas,
    String mesReferencia,
  ) {
    if (alertas.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Notificações de Gestão ($mesReferencia)',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.blueGrey,
          ),
        ),
        const SizedBox(height: 16),
        ...alertas.map((alerta) => _buildModernAlertCard(alerta)),
      ],
    );
  }

  Widget _buildClimaCard() {
    return Container(
      // ... (Restante do método inalterado)
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _climaData['cor'].withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _climaData['icone'],
                      color: _climaData['cor'],
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Clima em Tempo Real',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: Text(
                          _climaData['cidade'] ?? 'Detectando...',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              IconButton(
                icon: Icon(
                  Icons.edit_location_alt_outlined,
                  color: Colors.blue.shade600,
                ),
                tooltip: 'Mudar Cidade',
                onPressed: _mostrarBottomSheetSelecionarCidade,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${_climaData['temperatura']}°C',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Text(
                _climaData['condicao'],
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.blueGrey.shade600,
                ),
              ),
            ],
          ),

          if (_climaData['temperatura'] != '--') ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMiniClimaInfo(
                  Icons.water_drop,
                  'Umidade',
                  _climaData['umidade'],
                  Colors.blue,
                ),
                _buildMiniClimaInfo(
                  Icons.wb_twilight,
                  'Sol',
                  _climaData['sol'],
                  Colors.orange,
                ),
              ],
            ),
            if (_climaData['previsao_amanha'] != '') ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _climaData['previsao_amanha'],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildMiniClimaInfo(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEnvironmentalCard(double totalGerado) {
    double arvores = totalGerado / 400;
    double co2Kg = totalGerado * 0.10;
    double co2Ton = co2Kg / 1000;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.forest, color: Colors.green, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Impacto Ambiental Evitado',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '~${arvores.toStringAsFixed(0)} Árvores',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800,
                      ),
                    ),
                    Text(
                      co2Ton < 1
                          ? '~${co2Kg.toStringAsFixed(0)} kg CO₂'
                          : '~${co2Ton.toStringAsFixed(2)} ton CO₂',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernAlertCard(Map<String, dynamic> alerta) {
    Color cor;
    Color corFundoIcone;
    String titulo = alerta['titulo'] ?? 'Aviso';

    if (alerta['tipo'] == 'otimizacao_rateio') {
      cor = Colors.green.shade600;
      corFundoIcone = Colors.green.shade50;
    } else if (alerta['cor'] == 'red' ||
        alerta['tipo'] == 'creditos_desviados' ||
        alerta['tipo'] == 'deficit_real' ||
        alerta['tipo'] == 'fraude_repasse' ||
        alerta['tipo'] == 'concessionaria_fora_aneel') {
      cor = Colors.red.shade600;
      corFundoIcone = Colors.red.shade50;
    } else {
      cor = Colors.orange.shade600;
      corFundoIcone = Colors.orange.shade50;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color.fromARGB(97, 48, 101, 248)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: corFundoIcone,
              shape: BoxShape.circle,
            ),
            child: Icon(_getIconForType(alerta['tipo']), color: cor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(
                  titulo.replaceAll('🚨 ', ''),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey.shade900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  alerta['mensagem'],
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIconForType(String? tipo) {
    switch (tipo) {
      case 'baixa_producao':
      case 'queda_acentuada':
        return Icons.trending_down_rounded;
      case 'consumo_reserva':
        return Icons.hourglass_bottom_rounded;
      case 'deficit_real':
      case 'deficit_parcial':
      case 'custo_fixo_alto':
        return Icons.monetization_on_outlined;
      case 'creditos_desviados':
        return Icons.policy_outlined;
      case 'fraude_repasse':
        return Icons.compare_arrows_rounded;
      case 'concessionaria_fora_aneel':
        return Icons.gavel_rounded;
      case 'otimizacao_rateio':
        return Icons.lightbulb_outline_rounded;
      case 'fuga_dinheiro':
        return Icons.bolt_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  Widget _buildWaveChartCard(DashboardProvider dash, {bool isMobile = false}) {
    List<MapEntry<DateTime, double>> dados = _obterDadosGrafico(dash);
    double totalPeriodo = 0;
    for (var d in dados) {
      totalPeriodo += d.value;
    }

    return Container(
      height: isMobile ? 300 : 340,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blueGrey.shade900, Colors.black87],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.blueGrey.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dados.isEmpty
                        ? 'Sem dados'
                        : 'Geração (${dados.length} meses)',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${numeroFormat.format(totalPeriodo)} kWh',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isMobile ? 22 : 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.waves, color: Colors.orangeAccent, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'Produção',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (dados.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'Nenhum lançamento encontrado.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                ),
              ),
            )
          else
            Expanded(
              child: CustomPaint(
                painter: _WaveChartPainter(dados),
                child: Container(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFiltro(DashboardProvider dash) {
    final usinasGeradoras = dash
        .getTodasUsinas()
        .where((u) => u.isGeradora)
        .toList();
    Usina? usinaValidaParaDropdown;
    if (dash.usinaSelecionada != null && dash.usinaSelecionada!.isGeradora) {
      usinaValidaParaDropdown = dash.usinaSelecionada;
    }

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Usina?>(
          value: usinaValidaParaDropdown,
          hint: const Text('Todas as Geradoras'),
          isExpanded: true,
          icon: const Icon(Icons.filter_list, color: Colors.deepOrange),
          items: [
            const DropdownMenuItem<Usina?>(
              value: null,
              child: Text(
                'Todas as Geradoras',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ...usinasGeradoras.map(
              (usina) => DropdownMenuItem<Usina?>(
                value: usina,
                child: Text(usina.nome, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          onChanged: (u) => dash.selecionarUsina(u),
        ),
      ),
    );
  }

  Widget _buildModernKpi(
    String title,
    String value,
    IconData icon,
    Color color, {
    bool bgLight = false,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: bgLight
            ? Border.all(color: Colors.green.withValues(alpha: 0.2))
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey.shade900,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                title,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              if (subtitle != null) ...[
                const SizedBox(width: 4),
                Text(
                  '• $subtitle',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGaugeCardWeb(
    DashboardProvider dash,
    double taxa,
    Color cor,
    String status,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Balanço do Mês',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    dash.nomeMesReferencia,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: cor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 150,
            width: 150,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: 1.0,
                  valueColor: AlwaysStoppedAnimation(Colors.grey.shade100),
                  strokeWidth: 12,
                ),
                CircularProgressIndicator(
                  value: taxa.clamp(0.0, 1.0),
                  valueColor: AlwaysStoppedAnimation(cor),
                  strokeWidth: 12,
                  strokeCap: StrokeCap.round,
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(taxa * 100).toInt()}%',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Cobertura',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildRowGaugeDetail(
                  'Produção',
                  '${numeroFormat.format(dash.geracaoMensal)} kWh',
                  Colors.orange,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1),
                ),
                _buildRowGaugeDetail(
                  'Consumo',
                  '${numeroFormat.format(dash.consumoMensalReal)} kWh',
                  Colors.blue,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRowGaugeDetail(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            CircleAvatar(radius: 4, backgroundColor: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ],
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildTechSummary(DashboardProvider dash) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Especificações',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 16),
          _buildTechRow(
            Icons.solar_power,
            'Potência',
            '${dash.potenciaInstaladaNominal.toStringAsFixed(1)} kWp',
          ),
          const SizedBox(height: 12),
          _buildTechRow(
            Icons.settings_input_component,
            'Eficiência',
            '${dash.eficienciaGlobalMedia.toStringAsFixed(1)}%',
          ),
          const SizedBox(height: 12),
          _buildTechRow(
            Icons.share_location,
            'Distribuição',
            dash.totalEnergiaDistribuida > 0 ? 'Distribuindo' : 'Sem Repasses',
          ),
        ],
      ),
    );
  }

  Widget _buildTechRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade400),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildCardEconomia(DashboardProvider dash) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade600, Colors.green.shade800],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'ECONOMIA ACUMULADA',
            style: TextStyle(
              color: Colors.white70,
              letterSpacing: 1.5,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            moedaFormat.format(dash.totalEconomizado),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(color: Colors.white24),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.account_balance_wallet,
                color: Colors.white70,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Saldo de Créditos: ',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              Text(
                '${numeroFormat.format(dash.saldoCreditosTotal)} kWh',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardBalanco(
    DashboardProvider dash,
    Color corCobertura,
    String textoCobertura,
    double taxa,
    String frase,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Balanço do Mês',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    dash.nomeMesReferencia,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: corCobertura.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  textoCobertura,
                  style: TextStyle(
                    color: corCobertura,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Produção',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '${numeroFormat.format(dash.geracaoMensal)} kWh',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.compare_arrows, color: Colors.grey, size: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Consumo',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '${numeroFormat.format(dash.consumoMensalReal)} kWh',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: taxa.clamp(0.0, 1.0),
              backgroundColor: Colors.blue.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(
                taxa >= 1.0 ? Colors.green : Colors.orange,
              ),
              minHeight: 12,
            ),
          ),
          if (dash.consumoMensalReal > 0) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: corCobertura.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: corCobertura.withValues(alpha: 0.2)),
              ),
              child: Text(
                frase,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: corCobertura,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildListaDistribuicaoGeradora(DashboardProvider dash) {
    if (dash.usinaSelecionada == null ||
        dash.usinaSelecionada!.beneficiarias.isEmpty) {
      return const SizedBox.shrink();
    }

    final boxLancamentos = Hive.box<LancamentoMensal>('lancamentos');
    final lancamentos = boxLancamentos.values
        .where((l) => l.usinaId == dash.usinaSelecionada!.id && !l.isDeletado)
        .toList();

    if (lancamentos.isEmpty) return const SizedBox.shrink();

    lancamentos.sort((a, b) => b.dataReferencia.compareTo(a.dataReferencia));
    final ultimo = lancamentos.first;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.share, size: 16, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ÚLTIMO RATEIO (${dash.nomeMesReferencia})',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                    letterSpacing: 1.0,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...dash.usinaSelecionada!.beneficiarias.map((b) {
            double repasseTeorico =
                CalculadoraEnergetica.obterCreditoRepassadoParaFilha(
                  dash.usinaSelecionada!,
                  ultimo,
                  b.idUsinaFilha,
                );

            double repasseReal = 0;
            bool temLancamentoReal = false;

            try {
              final lancFilha = boxLancamentos.values.firstWhere(
                (l) =>
                    l.usinaId == b.idUsinaFilha &&
                    !l.isDeletado &&
                    l.dataReferencia.year == ultimo.dataReferencia.year &&
                    l.dataReferencia.month == ultimo.dataReferencia.month,
              );
              if (lancFilha.energiaInjetadaKwh > 0) {
                repasseReal = lancFilha.energiaInjetadaKwh;
                temLancamentoReal = true;
              }
            } catch (_) {}

            double valorExibido = temLancamentoReal
                ? repasseReal
                : repasseTeorico;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${b.nome} (${b.percentual.toStringAsFixed(0)}%)',
                      style: TextStyle(
                        color: Colors.blueGrey.shade700,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${numeroFormat.format(valorExibido)} kWh Real',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.blue.shade700,
                        ),
                      ),
                      if (temLancamentoReal &&
                          (repasseTeorico - repasseReal) > 0.5)
                        Text(
                          'Teórico: ${numeroFormat.format(repasseTeorico)} kWh',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade700,
                          ),
                        )
                      else if (!temLancamentoReal)
                        Text(
                          'Teórico (Pendente Lanc.)',
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.blueGrey.shade400,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStatsRow(DashboardProvider dash) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildStatCard(
                'Potência Instalada',
                '${dash.potenciaInstaladaNominal.toStringAsFixed(1)} kWp',
                Icons.solar_power,
                Colors.orange,
                subInfo:
                    'Eficiência: ${dash.eficienciaGlobalMedia.toStringAsFixed(1)}%',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                'Energia Distribuída',
                '${(dash.totalEnergiaDistribuida / 1000).toStringAsFixed(1)} MWh',
                Icons.share,
                Colors.blue,
                subInfo: 'Vitalicio Pelas Geradoras',
              ),
            ),
          ],
        ),
        _buildListaDistribuicaoGeradora(dash),
      ],
    );
  }

  Widget _buildCardROI(
    double percentualRoi,
    double investido,
    double retorno,
    int usinasIgnoradas,
  ) {
    double falta = investido - retorno;
    bool sePagou = falta <= 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    'ROI (Retorno)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  if (usinasIgnoradas > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Tooltip(
                        message:
                            "O cálculo ignora $usinasIgnoradas usina(s) sem custo de investimento cadastrado.",
                        triggerMode: TooltipTriggerMode.tap,
                        child: Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.orange[300],
                        ),
                      ),
                    ),
                ],
              ),
              if (sePagou)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    "PAGO E LUCRANDO",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${percentualRoi.toStringAsFixed(1)} %',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: sePagou ? Colors.green : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          if (!sePagou)
            Text(
              'FALTA: ${moedaFormat.format(falta)}',
              style: const TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            )
          else
            Text(
              'LUCRO LÍQUIDO: ${moedaFormat.format(retorno - investido)}',
              style: const TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          if (usinasIgnoradas > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: Text(
                "* Baseado apenas nas usinas com investimento cadastrado.",
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[400],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    String? subInfo,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          if (subInfo != null) ...[
            const SizedBox(height: 8),
            Text(
              subInfo,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ===========================================================================
// PAINTER DO GRÁFICO EM ONDA (CURVAS DE BEZIER)
// ===========================================================================
class _WaveChartPainter extends CustomPainter {
  final List<MapEntry<DateTime, double>> dados;
  _WaveChartPainter(this.dados);

  @override
  void paint(Canvas canvas, Size size) {
    if (dados.isEmpty) return;

    double maxVal = 0;
    for (var d in dados) {
      if (d.value > maxVal) maxVal = d.value;
    }
    if (maxVal == 0) maxVal = 1;

    double paddingTop = 40.0;
    double paddingBottom = 30.0;
    double chartHeight = size.height - paddingTop - paddingBottom;
    double chartBottomY = size.height - paddingBottom;

    double marginX = 20.0;
    double stepX = dados.length > 1
        ? (size.width - (marginX * 2)) / (dados.length - 1)
        : size.width / 2;

    List<Offset> points = [];

    for (int i = 0; i < dados.length; i++) {
      double x = marginX + (i * stepX);
      if (dados.length == 1) x = size.width / 2;

      double dy =
          paddingTop + chartHeight - ((dados[i].value / maxVal) * chartHeight);
      points.add(Offset(x, dy));
    }

    final path = Path();
    final fillPath = Path();

    if (points.length == 1) {
      path.moveTo(marginX, points[0].dy);
      path.lineTo(size.width - marginX, points[0].dy);

      fillPath.moveTo(marginX, chartBottomY);
      fillPath.lineTo(marginX, points[0].dy);
      fillPath.lineTo(size.width - marginX, points[0].dy);
      fillPath.lineTo(size.width - marginX, chartBottomY);
    } else {
      path.moveTo(points[0].dx, points[0].dy);
      fillPath.moveTo(points[0].dx, chartBottomY);
      fillPath.lineTo(points[0].dx, points[0].dy);

      for (int i = 0; i < points.length - 1; i++) {
        final p0 = points[i];
        final p1 = points[i + 1];

        final controlPointX = p0.dx + (p1.dx - p0.dx) / 2;

        path.cubicTo(controlPointX, p0.dy, controlPointX, p1.dy, p1.dx, p1.dy);

        fillPath.cubicTo(
          controlPointX,
          p0.dy,
          controlPointX,
          p1.dy,
          p1.dx,
          p1.dy,
        );
      }
      fillPath.lineTo(points.last.dx, chartBottomY);
    }

    fillPath.close();

    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.orangeAccent.withValues(alpha: 0.4),
        Colors.orangeAccent.withValues(alpha: 0.0),
      ],
    );

    final paintFill = Paint()
      ..shader = gradient.createShader(
        Rect.fromLTWH(0, paddingTop, size.width, chartHeight),
      );

    final paintLine = Paint()
      ..color = Colors.orangeAccent
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(fillPath, paintFill);
    canvas.drawPath(path, paintLine);

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final mesesAbrev = [
      'Jan',
      'Fev',
      'Mar',
      'Abr',
      'Mai',
      'Jun',
      'Jul',
      'Ago',
      'Set',
      'Out',
      'Nov',
      'Dez',
    ];

    final paintDot = Paint()
      ..color = Colors.blueGrey.shade900
      ..style = PaintingStyle.fill;
    final paintDotBorder = Paint()
      ..color = Colors.orangeAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], 5, paintDot);
      canvas.drawCircle(points[i], 5, paintDotBorder);

      String mesLabel = mesesAbrev[dados[i].key.month - 1];
      textPainter.text = TextSpan(
        text: mesLabel,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.6),
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(points[i].dx - (textPainter.width / 2), chartBottomY + 12),
      );

      double valor = dados[i].value;
      String valorFormatado = valor >= 1000
          ? '${(valor / 1000).toStringAsFixed(1).replaceAll('.0', '')}k'
          : valor.toStringAsFixed(0);

      textPainter.text = TextSpan(
        text: valorFormatado,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(points[i].dx - (textPainter.width / 2), points[i].dy - 24),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
