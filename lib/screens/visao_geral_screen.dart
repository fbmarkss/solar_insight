// Caminho: lib/screens/visao_geral_screen.dart
// Descrição: Dashboard Híbrido com Navegador Aninhado, Clima Real e FAB Verde.
// ATUALIZAÇÃO: Pull-to-Refresh com Feedback Padronizado via AppFeedback.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import '../services/dashboard_provider.dart';
import '../models/usina.dart';
import '../models/lancamento.dart';
import '../services/sincronizacao_service.dart';
import '../utils/app_feedback.dart'; // <-- IMPORT ADICIONADO PARA O PADRÃO DE FEEDBACK
import 'lancamento_mensal_screen.dart';

class VisaoGeralScreen extends StatefulWidget {
  const VisaoGeralScreen({super.key});

  @override
  State<VisaoGeralScreen> createState() => _VisaoGeralScreenState();
}

class _VisaoGeralScreenState extends State<VisaoGeralScreen> {
  final moedaFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final numeroFormat = NumberFormat.decimalPattern('pt_BR');

  // Navegador independente que não esconde o Menu Lateral na Web
  final GlobalKey<NavigatorState> _nestedNavKey = GlobalKey<NavigatorState>();

  // Estado inicial do Clima (Atualizado via HG Brasil na Web)
  Map<String, dynamic> _climaData = {
    'condicao': 'Carregando clima...',
    'temperatura': '--',
    'icone': Icons.cloud_outlined,
    'cor': Colors.grey,
    'cidade': null,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<DashboardProvider>(context, listen: false).atualizar();
    });

    // Chama a API de clima apenas se for Web
    if (kIsWeb) {
      _buscarClimaReal();
    }
  }

  // --- INTEGRAÇÃO HG BRASIL (WEB) ---
  Future<void> _buscarClimaReal() async {
    try {
      final url = Uri.parse(
        // Adicionada a sua chave (key=c791cabd) para liberar o acesso na Web!
        'https://api.hgbrasil.com/weather?format=json-cors&key=c791cabd&user_ip=remote',
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'];

        if (mounted) {
          setState(() {
            _climaData = {
              'condicao': results['description'],
              'temperatura': results['temp'],
              'icone': _obterIconeHg(results['condition_slug']),
              'cor': _obterCorHg(results['condition_slug']),
              'cidade': results['city'],
            };
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao buscar clima: $e');
      if (mounted) {
        setState(() {
          _climaData['condicao'] = 'Clima indisponível';
        });
      }
    }
  }

  IconData _obterIconeHg(String slug) {
    switch (slug) {
      case 'clear_day':
        return Icons.wb_sunny_rounded;
      case 'clear_night':
        return Icons.nightlight_round;
      case 'cloud':
      case 'cloudly_day':
      case 'cloudly_night':
        return Icons.cloud_rounded;
      case 'rain':
        return Icons.water_drop_rounded;
      case 'storm':
        return Icons.thunderstorm_rounded;
      case 'snow':
        return Icons.ac_unit_rounded;
      default:
        return Icons.cloud_outlined;
    }
  }

  Color _obterCorHg(String slug) {
    if (slug.contains('clear')) return Colors.orange;
    if (slug.contains('rain') || slug.contains('storm')) return Colors.blue;
    return Colors.blueGrey;
  }
  // ------------------------------------

  // --- NOVA LÓGICA DE PULL-TO-REFRESH COM FEEDBACK PADRONIZADO ---
  Future<void> _handleRefresh() async {
    Provider.of<DashboardProvider>(context, listen: false).atualizar();
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
      // Ignora erros no refresh visual
    }
  }

  // --- LÓGICA MESTRA DE NAVEGAÇÃO ---
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
      // Abre a tela de forma nativa e suave dentro da gaiola direita da Web
      _nestedNavKey.currentState!.push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => tela,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } else {
      // Abre a tela normal no mobile
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
    // Verifica a largura real do navegador
    bool isWeb = MediaQuery.of(context).size.width >= 900;

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
          frasePercentual = "Você produziu $percentual% do seu consumo";

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

        return LayoutBuilder(
          builder: (context, constraints) {
            // Decide se o conteúdo é "Largo" ou "Empilhado"
            bool isWidePanel = constraints.maxWidth >= 1000;

            return Scaffold(
              backgroundColor: const Color(0xFFF5F7FA),
              body: isWidePanel
                  ? _buildWebLayout(
                      dash,
                      filtro,
                      cardAmbiental,
                      taxaCoberturaMensal,
                      corCobertura,
                      textoCobertura,
                      percentualRoi,
                      navContext,
                      isWeb,
                    )
                  : _buildMobileLayout(
                      dash,
                      filtro,
                      cardAmbiental,
                      taxaCoberturaMensal,
                      corCobertura,
                      textoCobertura,
                      percentualRoi,
                      frasePercentual,
                      navContext,
                      isWeb,
                    ),

              // =========================================================
              // BOTÃO FLUTUANTE (FAB) VERDE PARA MOBILE E TABLET
              // =========================================================
              floatingActionButton: isWidePanel
                  ? null // Se for ecrã Largo, o botão já está no Topo da Toolbar
                  : FloatingActionButton.extended(
                      onPressed: () => _abrirLancamento(
                        isWeb,
                        navContext,
                        usina: dash.usinaSelecionada,
                      ),
                      backgroundColor: const Color.fromARGB(
                        255,
                        235,
                        136,
                        90,
                      ), // Cor Verde Solicitada
                      foregroundColor: Colors.white,
                      icon: const Icon(Icons.add),
                      label: const Text(
                        'LANÇAMENTO',
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

  // =====================================================================
  // LAYOUT WEB RESPONSIVO (WRAP)
  // =====================================================================
  Widget _buildWebLayout(
    DashboardProvider dash,
    Widget filtro,
    Widget cardAmbiental,
    double taxaCoberturaMensal,
    Color corCobertura,
    String textoCobertura,
    double percentualRoi,
    BuildContext context,
    bool isWeb,
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
            // HEADER FLUIDO (Wrap impede o Overflow)
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
                // TOOLBAR PADRONIZADA
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
                    _buildWeatherPill(_climaData),
                    SizedBox(width: 250, child: filtro),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 32),

            // GRID PRINCIPAL
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildMainChartCard(dash),
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
                      _buildAlertasSection(dash.alertasDoSistema),
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
                      cardAmbiental,
                      const SizedBox(height: 24),
                      _buildTechSummary(dash),
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

  // =====================================================================
  // LAYOUT MOBILE (Usado para Telemóveis e Tablets)
  // =====================================================================
  Widget _buildMobileLayout(
    DashboardProvider dash,
    Widget filtro,
    Widget cardAmbiental,
    double taxaCoberturaMensal,
    Color corCobertura,
    String textoCobertura,
    double percentualRoi,
    String frasePercentual,
    BuildContext context,
    bool isWeb,
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
          _buildMainChartCard(dash, isMobile: true),
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
          cardAmbiental,
          const SizedBox(height: 24),
          if (dash.alertasDoSistema.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                'NOTIFICAÇÕES DE GESTÃO',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            ...dash.alertasDoSistema.map(
              (alerta) => _buildAlertaDiscreto(alerta),
            ),
          ],
          const SizedBox(
            height: 100,
          ), // Espaço para o botão flutuante não cobrir conteúdo
        ],
      ),
    );
  }

  // ===========================================================================
  // WIDGETS DE ALERTAS
  // ===========================================================================

  Widget _buildAlertasSection(List<Map<String, dynamic>> alertas) {
    if (alertas.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Atenção Necessária',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.blueGrey,
          ),
        ),
        const SizedBox(height: 12),
        ...alertas.map((alerta) => _buildAlertaDiscreto(alerta, isWeb: true)),
      ],
    );
  }

  Widget _buildAlertaDiscreto(
    Map<String, dynamic> alerta, {
    bool isWeb = false,
  }) {
    Color cor = alerta['cor'] == 'red'
        ? Colors.red.shade700
        : Colors.orange.shade700;
    String prioridade =
        alerta['tipo'] == 'deficit_real' || alerta['tipo'] == 'queda_acentuada'
        ? 'Alta'
        : 'Média';
    Color prioridadeCor = prioridade == 'Alta' ? Colors.red : Colors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isWeb
            ? Border(left: BorderSide(color: prioridadeCor, width: 4))
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(_getIconForType(alerta['tipo']), color: cor, size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      alerta['titulo'],
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (isWeb) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: prioridadeCor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          prioridade,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: prioridadeCor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  alerta['mensagem'],
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (isWeb) Icon(Icons.chevron_right, color: Colors.grey.shade400),
        ],
      ),
    );
  }

  IconData _getIconForType(String? tipo) {
    switch (tipo) {
      case 'baixa_producao':
        return Icons.warning_amber_rounded;
      case 'queda_acentuada':
        return Icons.trending_down_rounded;
      case 'consumo_reserva':
        return Icons.hourglass_bottom_rounded;
      case 'deficit_real':
        return Icons.error_outline_rounded;
      case 'distribuicao':
        return Icons.alt_route_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  // ===========================================================================
  // WIDGETS COMUNS
  // ===========================================================================

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
      height: 48, // Altura padronizada
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12), // Raio padronizado
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Usina?>(
          value: usinaValidaParaDropdown,
          hint: const Text('Todas as Unidades'),
          isExpanded: true,
          icon: const Icon(Icons.filter_list, color: Colors.deepOrange),
          items: [
            const DropdownMenuItem<Usina?>(
              value: null,
              child: Text(
                'Todas as Unidades (Geral)',
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

  Widget _buildMainChartCard(DashboardProvider dash, {bool isMobile = false}) {
    List<MapEntry<DateTime, double>> dados = _obterDadosGrafico(dash);
    double totalPeriodo = 0;
    double maxGeracao = 0;
    for (var d in dados) {
      totalPeriodo += d.value;
      if (d.value > maxGeracao) maxGeracao = d.value;
    }
    if (maxGeracao == 0) maxGeracao = 1;

    const mesesAbrev = [
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

    return Container(
      height: isMobile ? 300 : 340,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blueGrey.shade800, Colors.blueGrey.shade900],
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
                    Icon(Icons.bar_chart, color: Colors.greenAccent, size: 16),
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
            Center(
              child: Text(
                'Nenhum lançamento encontrado.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              ),
            )
          else
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final width = box.maxWidth;
                  final espacamento = 10.0;
                  final barWidth = (width / dados.length) - espacamento;
                  double maxBarHeight = box.maxHeight - 50;
                  if (maxBarHeight < 10) maxBarHeight = 10;

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: dados.map((entry) {
                      final data = entry.key;
                      final valor = entry.value;
                      final barHeight = (valor / maxGeracao) * maxBarHeight;
                      final isUltimoMes = entry == dados.last;

                      return Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            NumberFormat.compact().format(valor),
                            style: TextStyle(
                              color: isUltimoMes
                                  ? Colors.orange
                                  : Colors.white.withValues(alpha: 0.7),
                              fontSize: 10,
                              fontWeight: isUltimoMes
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Tooltip(
                            message:
                                '${mesesAbrev[data.month - 1]} ${data.year}\n${valor.toStringAsFixed(1)} kWh',
                            child: Container(
                              width: barWidth,
                              height: barHeight > 0 ? barHeight : 4,
                              decoration: BoxDecoration(
                                color: isUltimoMes
                                    ? Colors.orange
                                    : Colors.white.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            mesesAbrev[data.month - 1],
                            style: TextStyle(
                              color: isUltimoMes
                                  ? Colors.orange
                                  : Colors.white.withValues(alpha: 0.6),
                              fontSize: 11,
                              fontWeight: isUltimoMes
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEnvironmentalCard(double totalGerado) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.forest, color: Colors.green, size: 28),
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Impacto Ambiental',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '~${(totalGerado / 400).toStringAsFixed(0)} Árvores preservadas',
                style: TextStyle(fontSize: 16, color: Colors.green.shade800),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // WIDGETS EXCLUSIVOS WEB
  // ===========================================================================

  Widget _buildWeatherPill(Map<String, dynamic> clima) {
    return Container(
      height: 48, // Altura padronizada
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12), // Raio padronizado
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(clima['icone'], color: clima['cor'], size: 20),
          const SizedBox(width: 8),
          Text(
            '${clima['temperatura']}°C',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Text(
            clima['cidade'] != null
                ? '${clima['condicao']} em ${clima['cidade']}'
                : clima['condicao'],
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ],
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
              const Text(
                'Balanço',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
            'Unidades',
            dash.totalEnergiaDistribuida > 0 ? 'Ativas' : 'Inativas',
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

  // ===========================================================================
  // WIDGETS EXCLUSIVOS MOBILE
  // ===========================================================================

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

  Widget _buildStatsRow(DashboardProvider dash) {
    return Row(
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
            subInfo: 'Beneficiárias',
          ),
        ),
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
