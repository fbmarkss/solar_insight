// Caminho: lib/screens/tabs/auditoria_global_tab.dart
// Descrição: Aba de Análise Global com Filtro Dinâmico Inteligente e Gráficos em Onda.

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../models/usina.dart';
import '../../models/lancamento.dart';
import '../../services/sincronizacao_service.dart';
import '../../utils/app_feedback.dart';
import '../../utils/calculadora_energetica.dart';

class AuditoriaGlobalTab extends StatefulWidget {
  const AuditoriaGlobalTab({super.key});

  @override
  State<AuditoriaGlobalTab> createState() => _AuditoriaGlobalTabState();
}

class _AuditoriaGlobalTabState extends State<AuditoriaGlobalTab> {
  // Padrão alterado para 'ANO' para manter o gráfico limpo e legível
  String _filtroSelecionado = 'ANO';

  Future<void> _handleRefresh(BuildContext context) async {
    try {
      final resultado = await SincronizacaoService().sincronizarTudo();
      if (!context.mounted) return;
      if (resultado.contains('Erro') ||
          resultado.contains('Sem internet') ||
          resultado.contains('offline')) {
        AppFeedback.show(context, resultado, isError: true);
      } else if (resultado == 'Sincronizado.') {
        AppFeedback.show(context, "Tudo já está sincronizado.", isError: false);
      } else {
        AppFeedback.show(context, "Dados atualizados!", isError: false);
      }
    } catch (e) {
      if (context.mounted) {
        AppFeedback.show(context, "Erro ao atualizar: $e", isError: true);
      }
    }
  }

  // Novo Filtro Baseado na Data Mais Recente do Banco de Dados
  bool _isDentroDoFiltro(DateTime dataRef, DateTime dataBase) {
    if (_filtroSelecionado == 'TUDO') return true;

    DateTime dataLimite;

    if (_filtroSelecionado == '6M') {
      dataLimite = DateTime(dataBase.year, dataBase.month - 5, 1);
    } else if (_filtroSelecionado == '12M') {
      dataLimite = DateTime(dataBase.year, dataBase.month - 11, 1);
    } else {
      // ANO
      dataLimite = DateTime(dataBase.year, 1, 1);
    }

    if (_filtroSelecionado == 'ANO' && dataRef.year != dataBase.year) {
      return false;
    }
    return dataRef.isAfter(dataLimite.subtract(const Duration(days: 1)));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Hive.box<LancamentoMensal>('lancamentos').listenable(),
      builder: (context, Box<LancamentoMensal> boxLancamentos, _) {
        final todosLancs = boxLancamentos.values
            .where((l) => !l.isDeletado)
            .toList();

        if (todosLancs.isEmpty) {
          return RefreshIndicator(
            color: Colors.deepOrange,
            backgroundColor: Colors.white,
            onRefresh: () => _handleRefresh(context),
            child: const CustomScrollView(
              physics: AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.analytics_outlined,
                          size: 48,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          "Sem dados para análise global.",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // Descobre qual a fatura mais recente lançada para alinhar o filtro
        DateTime dataBaseFiltro = DateTime.now();
        if (todosLancs.isNotEmpty) {
          dataBaseFiltro = todosLancs
              .map((l) => l.dataReferencia)
              .reduce((a, b) => a.isAfter(b) ? a : b);
        }

        final boxUsinas = Hive.box<Usina>('usinas');
        final usinas = boxUsinas.values.where((u) => !u.isDeletado).toList();

        double totalGeralGerado = 0;
        double totalGeralConsumido = 0;
        Map<String, double> consumoPorUsina = {};
        Map<String, Map<String, dynamic>> dadosMensais = {};

        // Processa usina por usina para não quebrar a ordem cronológica
        for (var usina in usinas) {
          final lancsDaUsina = todosLancs
              .where((l) => l.usinaId == usina.id)
              .toList();
          lancsDaUsina.sort(
            (a, b) => a.dataReferencia.compareTo(b.dataReferencia),
          );

          for (var l in lancsDaUsina) {
            // Roda o cálculo para manter o histórico de saldo alimentado
            final resumo = CalculadoraEnergetica.gerarResumoMesOficial(
              usina,
              l,
            );

            // Mas só desenha os dados se o mês passar no Filtro
            if (_isDentroDoFiltro(l.dataReferencia, dataBaseFiltro)) {
              String key = DateFormat('yyyyMM').format(l.dataReferencia);
              String display = DateFormat(
                'MMM',
                'pt_BR',
              ).format(l.dataReferencia).toUpperCase();

              if (l.dataReferencia.year != DateTime.now().year) {
                display = DateFormat(
                  'MMM/yy',
                  'pt_BR',
                ).format(l.dataReferencia).toUpperCase();
              }

              dadosMensais.putIfAbsent(
                key,
                () => {
                  'mes': display,
                  'geracao': 0.0,
                  'consumo': 0.0,
                  'custo': 0.0,
                  'custoProjetado': 0.0,
                  'date': l.dataReferencia,
                },
              );

              double energiaEfetivamentePoupada = 0;

              if (usina.isGeradora) {
                totalGeralGerado += resumo.geracaoTotal;
                dadosMensais[key]!['geracao'] += resumo.geracaoTotal;

                double energiaCompensada = l.energiaInjetadaKwh.clamp(
                  0.0,
                  l.energiaConsumidaRedeKwh,
                );
                energiaEfetivamentePoupada =
                    resumo.autoconsumo + energiaCompensada;
              } else {
                double energiaCompensada = resumo.injetadoOuRecebido.clamp(
                  0.0,
                  l.energiaConsumidaRedeKwh,
                );
                energiaEfetivamentePoupada = energiaCompensada;
              }

              double economiaFinanceira =
                  energiaEfetivamentePoupada * l.tarifaKwh;
              double custoProjetado = l.valorFaturaR + economiaFinanceira;

              totalGeralConsumido += resumo.consumoRealLocal;
              dadosMensais[key]!['consumo'] += resumo.consumoRealLocal;
              dadosMensais[key]!['custo'] += l.valorFaturaR;
              dadosMensais[key]!['custoProjetado'] += custoProjetado;

              consumoPorUsina[usina.nome] =
                  (consumoPorUsina[usina.nome] ?? 0) + resumo.consumoRealLocal;
            }
          }
        }

        List<Map<String, dynamic>> graficoOrdenado = dadosMensais.values
            .toList();
        graficoOrdenado.sort(
          (a, b) => (a['date'] as DateTime).compareTo(b['date']),
        );

        List<MapEntry<String, double>> rankingOrdenado = consumoPorUsina.entries
            .toList();
        rankingOrdenado.sort((a, b) => b.value.compareTo(a.value));

        return LayoutBuilder(
          builder: (context, constraints) {
            bool isWeb = constraints.maxWidth >= 900;

            return RefreshIndicator(
              color: Colors.deepOrange,
              backgroundColor: Colors.white,
              onRefresh: () => _handleRefresh(context),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(isWeb ? 32 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: isWeb
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Visão Global",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 24,
                                color: Colors.black87,
                              ),
                            ),
                            Text(
                              "Balanço total da empresa.",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        if (isWeb)
                          _buildFiltrosRow()
                        else
                          const SizedBox.shrink(),
                      ],
                    ),
                    if (!isWeb) ...[
                      const SizedBox(height: 16),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: _buildFiltrosRow(),
                      ),
                    ],
                    const SizedBox(height: 24),

                    if (isWeb) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 1,
                            child: _buildTermometroCard(
                              totalGeralGerado,
                              totalGeralConsumido,
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 2,
                            child: _buildRankingCard(
                              rankingOrdenado,
                              totalGeralConsumido,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 1,
                            child: _buildBalancoLinhasCard(graficoOrdenado),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 1,
                            child: _buildGeracaoLinhaCard(graficoOrdenado),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 1,
                            child: _buildFinanceiroCard(graficoOrdenado),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 1,
                            child: _buildTopViloesCard(
                              todosLancs
                                  .where(
                                    (l) => _isDentroDoFiltro(
                                      l.dataReferencia,
                                      dataBaseFiltro,
                                    ),
                                  )
                                  .toList(),
                              boxUsinas,
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      _buildTermometroCard(
                        totalGeralGerado,
                        totalGeralConsumido,
                      ),
                      const SizedBox(height: 16),
                      _buildRankingCard(rankingOrdenado, totalGeralConsumido),
                      const SizedBox(height: 16),
                      _buildBalancoLinhasCard(graficoOrdenado),
                      const SizedBox(height: 16),
                      _buildGeracaoLinhaCard(graficoOrdenado),
                      const SizedBox(height: 16),
                      _buildFinanceiroCard(graficoOrdenado),
                      const SizedBox(height: 16),
                      _buildTopViloesCard(
                        todosLancs
                            .where(
                              (l) => _isDentroDoFiltro(
                                l.dataReferencia,
                                dataBaseFiltro,
                              ),
                            )
                            .toList(),
                        boxUsinas,
                      ),
                    ],
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFiltrosRow() {
    return Row(
      children: [
        // _buildFilterChip('Tudo', 'TUDO'),
        // const SizedBox(width: 8),
        _buildFilterChip('6 Meses', '6M'),
        const SizedBox(width: 8),
        _buildFilterChip('12 Meses', '12M'),
        const SizedBox(width: 8),
        _buildFilterChip('Este Ano', 'ANO'),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value) {
    bool isSelected = _filtroSelecionado == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: Colors.deepOrange.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: isSelected ? Colors.deepOrange : Colors.grey.shade700,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      backgroundColor: Colors.white,
      side: BorderSide(
        color: isSelected ? Colors.deepOrange : Colors.grey.shade300,
      ),
      onSelected: (bool selected) {
        if (selected) setState(() => _filtroSelecionado = value);
      },
    );
  }

  // 1. Termômetro
  Widget _buildTermometroCard(double geracao, double consumo) {
    double percentual = consumo > 0 ? (geracao / consumo) : 0.0;
    Color corGauage = percentual >= 1.0
        ? Colors.green
        : (percentual > 0.6 ? Colors.orange : Colors.red);

    return _buildBaseCard(
      titulo: "Autossuficiência",
      icone: Icons.thermostat,
      child: Column(
        children: [
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            width: 120,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: percentual.clamp(0.0, 1.0),
                  strokeWidth: 12,
                  backgroundColor: Colors.grey.shade100,
                  valueColor: AlwaysStoppedAnimation<Color>(corGauage),
                  strokeCap: StrokeCap.round,
                ),
                Center(
                  child: Text(
                    "${(percentual * 100).toStringAsFixed(0)}%",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: corGauage,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            percentual >= 1.0 ? "Operação Sustentável" : "Dependente da Rede",
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // 2. Ranking de Consumo
  Widget _buildRankingCard(
    List<MapEntry<String, double>> ranking,
    double totalConsumo,
  ) {
    final numFormat = NumberFormat.decimalPattern('pt_BR');

    return _buildBaseCard(
      titulo: "Ranking de Consumo",
      icone: Icons.format_list_numbered,
      child: ranking.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  "Sem consumo.",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          : Column(
              children: ranking.take(4).map((entry) {
                double perc = totalConsumo > 0
                    ? (entry.value / totalConsumo)
                    : 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              entry.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            "${numFormat.format(entry.value)} kWh (${(perc * 100).toStringAsFixed(0)}%)",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: perc,
                        backgroundColor: Colors.blue.withValues(alpha: 0.1),
                        valueColor: const AlwaysStoppedAnimation(Colors.blue),
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  // 3. Balanço Energético (Linhas Duplas)
  Widget _buildBalancoLinhasCard(List<Map<String, dynamic>> dados) {
    return _buildBaseCard(
      titulo: "Balanço Energético",
      icone: Icons.analytics_outlined,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem("Geração", Colors.orange),
              const SizedBox(width: 16),
              _buildLegendItem("Consumo", Colors.blue),
            ],
          ),
          const SizedBox(height: 16),
          if (dados.isEmpty)
            const SizedBox(
              height: 240,
              child: Center(
                child: Text(
                  "Sem dados suficientes",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            SizedBox(
              height: 240,
              width: double.infinity,
              child: CustomPaint(
                painter: _DoubleLineChartPainter(
                  dados,
                  Colors.orange,
                  Colors.blue,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 4. Gráfico de ONDA (Evolução da Geração)
  Widget _buildGeracaoLinhaCard(List<Map<String, dynamic>> dados) {
    return _buildBaseCard(
      titulo: "Evolução da Produção",
      icone: Icons.waves,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [_buildLegendItem("Produção Solar", Colors.orangeAccent)],
          ),
          const SizedBox(height: 16),
          if (dados.isEmpty)
            const SizedBox(
              height: 240,
              child: Center(
                child: Text(
                  "Sem dados suficientes",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            SizedBox(
              height: 240,
              width: double.infinity,
              child: CustomPaint(
                painter: _WaveChartPainter(dados, Colors.orangeAccent),
              ),
            ),
        ],
      ),
    );
  }

  // 5. Gráfico Financeiro (Custo Evitado - Barras)
  Widget _buildFinanceiroCard(List<Map<String, dynamic>> dados) {
    return _buildBaseCard(
      titulo: "Custo Evitado (Economia)",
      icone: Icons.savings_outlined,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // AQUI: A cor da legenda alterada para um azul suave que contrasta com o verde
              _buildLegendItem("Sem Solar (Projetado)", Colors.blue.shade300),
              const SizedBox(width: 16),
              _buildLegendItem("Com Solar (Real)", Colors.green),
            ],
          ),
          const SizedBox(height: 16),
          if (dados.isEmpty)
            const SizedBox(
              height: 240,
              child: Center(
                child: Text(
                  "Sem dados suficientes",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            SizedBox(
              height: 240,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: dados.map((d) {
                  double maxVal = _getMaxVal(dados, [
                    'custoProjetado',
                    'custo',
                  ]);
                  double maxBarHeight = 175;

                  double hFundo = (d['custoProjetado'] / maxVal) * maxBarHeight;
                  double hFrente = (d['custo'] / maxVal) * maxBarHeight;

                  return Expanded(
                    child: _buildColSobreposta(
                      d['mes'],
                      d['custoProjetado'],
                      d['custo'],
                      hFundo,
                      hFrente,
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // 6. Top Vilões (Design Mais Clean)
  Widget _buildTopViloesCard(
    List<LancamentoMensal> lancamentos,
    Box<Usina> boxUsinas,
  ) {
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    List<LancamentoMensal> ordenados = List.from(lancamentos);
    if (ordenados.isEmpty) {
      return _buildBaseCard(
        titulo: "Vilões do Mês",
        icone: Icons.warning_amber_rounded,
        child: const Center(
          child: Text(
            "Sem faturas no período.",
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    ordenados.sort((a, b) => b.dataReferencia.compareTo(a.dataReferencia));
    DateTime ultimaData = ordenados.last.dataReferencia;

    var doMes = ordenados
        .where(
          (l) =>
              l.dataReferencia.year == ultimaData.year &&
              l.dataReferencia.month == ultimaData.month,
        )
        .toList();
    doMes.sort((a, b) => b.valorFaturaR.compareTo(a.valorFaturaR));

    return _buildBaseCard(
      titulo:
          "Maiores Faturas (${DateFormat('MMM', 'pt_BR').format(ultimaData).toUpperCase()})",
      icone: Icons.monetization_on_outlined,
      child: Column(
        children: doMes.take(3).toList().asMap().entries.map((entry) {
          int rank = entry.key + 1;
          var l = entry.value;
          String nomeUsina = "Desconhecida";
          try {
            nomeUsina = boxUsinas.values
                .firstWhere((u) => u.id == l.usinaId)
                .nome;
          } catch (_) {}

          Color corRank = rank == 1
              ? Colors.red
              : (rank == 2 ? Colors.orange : Colors.amber);

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: corRank.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '#$rank',
                      style: TextStyle(
                        color: corRank,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    nomeUsina,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  moeda.format(l.valorFaturaR),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // --- AUXILIARES DE UI ---
  Widget _buildBaseCard({
    required String titulo,
    required IconData icone,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, size: 20, color: Colors.blueGrey),
              const SizedBox(width: 8),
              Text(
                titulo,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.blueGrey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  double _getMaxVal(List<Map<String, dynamic>> dados, List<String> keys) {
    double m = 0;
    for (var d in dados) {
      for (var k in keys) {
        if (d[k] > m) m = d[k];
      }
    }
    return m == 0 ? 1 : m;
  }

  Widget _buildColSobreposta(
    String mes,
    double vFundo,
    double vFrente,
    double hFundo,
    double hFrente,
  ) {
    hFundo = hFundo < 4 && vFundo > 0 ? 4 : hFundo;
    hFrente = hFrente < 4 && vFrente > 0 ? 4 : hFrente;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (vFundo > (vFrente + 1.0))
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              NumberFormat.compact().format(vFundo),
              style: TextStyle(
                fontSize: 8,
                // AQUI: Cor do texto "Projetado" alterada para azul
                color: Colors.blue.shade400,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            NumberFormat.compact().format(vFrente),
            style: const TextStyle(
              fontSize: 9,
              color: Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 24,
          height: hFundo,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Container(
                width: 18,
                height: hFundo,
                decoration: BoxDecoration(
                  // AQUI: A cor da barra alterada para um azul claro e suave
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Container(
                width: 10,
                height: hFrente,
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          mes,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: Colors.black54,
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// PAINTERS DOS GRÁFICOS (DUPLA LINHA E ONDA)
// ===========================================================================

class _DoubleLineChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> dados;
  final Color colorGeracao;
  final Color colorConsumo;

  _DoubleLineChartPainter(this.dados, this.colorGeracao, this.colorConsumo);

  @override
  void paint(Canvas canvas, Size size) {
    if (dados.isEmpty) return;

    double maxVal = 0;
    for (var d in dados) {
      if (d['geracao'] > maxVal) maxVal = d['geracao'];
      if (d['consumo'] > maxVal) maxVal = d['consumo'];
    }
    if (maxVal == 0) maxVal = 1;

    double paddingTop = 25.0;
    double paddingBottom = 25.0;
    double chartHeight = size.height - paddingTop - paddingBottom;
    double chartBottomY = size.height - paddingBottom;

    double marginX = 20.0;
    double stepX =
        (size.width - (marginX * 2)) /
        (dados.length > 1 ? (dados.length - 1) : 1);

    List<Offset> pointsG = [];
    List<Offset> pointsC = [];

    for (int i = 0; i < dados.length; i++) {
      double x = marginX + (i * stepX);
      if (dados.length == 1) x = size.width / 2;

      double dyG =
          paddingTop +
          chartHeight -
          ((dados[i]['geracao'] / maxVal) * chartHeight);
      double dyC =
          paddingTop +
          chartHeight -
          ((dados[i]['consumo'] / maxVal) * chartHeight);
      pointsG.add(Offset(x, dyG));
      pointsC.add(Offset(x, dyC));
    }

    _drawPath(
      canvas,
      size,
      pointsC,
      colorConsumo,
      chartHeight,
      paddingTop,
      chartBottomY,
    );
    _drawPath(
      canvas,
      size,
      pointsG,
      colorGeracao,
      chartHeight,
      paddingTop,
      chartBottomY,
    );

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i < dados.length; i++) {
      textPainter.text = TextSpan(
        text: dados[i]['mes'],
        style: const TextStyle(
          fontSize: 9,
          color: Colors.black54,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(pointsG[i].dx - (textPainter.width / 2), chartBottomY + 8),
      );

      if (dados[i]['geracao'] > 0) {
        textPainter.text = TextSpan(
          text: NumberFormat.compact().format(dados[i]['geracao']),
          style: TextStyle(
            fontSize: 9,
            color: colorGeracao,
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(pointsG[i].dx - (textPainter.width / 2), pointsG[i].dy - 16),
        );
      }

      if (dados[i]['consumo'] > 0) {
        textPainter.text = TextSpan(
          text: NumberFormat.compact().format(dados[i]['consumo']),
          style: TextStyle(
            fontSize: 9,
            color: colorConsumo,
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(pointsC[i].dx - (textPainter.width / 2), pointsC[i].dy + 8),
        );
      }
    }
  }

  void _drawPath(
    Canvas canvas,
    Size size,
    List<Offset> points,
    Color color,
    double chartHeight,
    double paddingTop,
    double chartBottomY,
  ) {
    if (points.isEmpty) return;
    final paintLine = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final paintDot = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final paintDotBorder = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    final fillPath = Path();

    if (points.length == 1) {
      path.moveTo(20, points[0].dy);
      path.lineTo(size.width - 20, points[0].dy);
    } else {
      path.moveTo(points[0].dx, points[0].dy);
      fillPath.moveTo(points[0].dx, chartBottomY);
      fillPath.lineTo(points[0].dx, points[0].dy);

      for (int i = 0; i < points.length; i++) {
        if (i == 0) {
          path.moveTo(points[i].dx, points[i].dy);
        } else {
          path.lineTo(points[i].dx, points[i].dy);
          fillPath.lineTo(points[i].dx, points[i].dy);
        }
      }
      fillPath.lineTo(points.last.dx, chartBottomY);
      fillPath.close();
    }

    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [color.withValues(alpha: 0.1), color.withValues(alpha: 0.0)],
    );
    final paintFill = Paint()
      ..shader = gradient.createShader(
        Rect.fromLTWH(0, paddingTop, size.width, chartHeight),
      );

    canvas.drawPath(fillPath, paintFill);
    canvas.drawPath(path, paintLine);

    for (var p in points) {
      canvas.drawCircle(p, 4, paintDot);
      canvas.drawCircle(p, 4, paintDotBorder);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// NOVO: Painter em ONDA (Curvas Suaves)
class _WaveChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> dados;
  final Color cor;

  _WaveChartPainter(this.dados, this.cor);

  @override
  void paint(Canvas canvas, Size size) {
    if (dados.isEmpty) return;

    double maxVal = 0;
    for (var d in dados) {
      if (d['geracao'] > maxVal) maxVal = d['geracao'];
    }
    if (maxVal == 0) maxVal = 1;

    double paddingTop = 30.0;
    double paddingBottom = 30.0;
    double chartHeight = size.height - paddingTop - paddingBottom;
    double chartBottomY = size.height - paddingBottom;

    double marginX = 20.0;
    double stepX =
        (size.width - (marginX * 2)) /
        (dados.length > 1 ? (dados.length - 1) : 1);

    List<Offset> points = [];

    for (int i = 0; i < dados.length; i++) {
      double x = marginX + (i * stepX);
      if (dados.length == 1) x = size.width / 2;

      double dy =
          paddingTop +
          chartHeight -
          ((dados[i]['geracao'] / maxVal) * chartHeight);
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
      colors: [cor.withValues(alpha: 0.3), cor.withValues(alpha: 0.0)],
    );

    final paintFill = Paint()
      ..shader = gradient.createShader(
        Rect.fromLTWH(0, paddingTop, size.width, chartHeight),
      );

    final paintLine = Paint()
      ..color = cor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(fillPath, paintFill);
    canvas.drawPath(path, paintLine);

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final paintDot = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final paintDotBorder = Paint()
      ..color = cor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], 4, paintDot);
      canvas.drawCircle(points[i], 4, paintDotBorder);

      textPainter.text = TextSpan(
        text: dados[i]['mes'],
        style: const TextStyle(
          fontSize: 9,
          color: Colors.black54,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(points[i].dx - (textPainter.width / 2), chartBottomY + 8),
      );

      if (dados[i]['geracao'] > 0) {
        textPainter.text = TextSpan(
          text: NumberFormat.compact().format(dados[i]['geracao']),
          style: TextStyle(
            fontSize: 9,
            color: cor,
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(points[i].dx - (textPainter.width / 2), points[i].dy - 16),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
