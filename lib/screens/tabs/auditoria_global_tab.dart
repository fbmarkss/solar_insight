// Caminho: lib/screens/tabs/auditoria_global_tab.dart
// Descrição: Aba de Análise Global (Balanço Energético + Vilões).
// Atualização: Layout Bento Grid para Web; Mobile com Scroll Horizontal no Gráfico para evitar Overflow em 12 Meses.

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../../models/usina.dart';
import '../../models/lancamento.dart';

class AuditoriaGlobalTab extends StatefulWidget {
  const AuditoriaGlobalTab({super.key});

  @override
  State<AuditoriaGlobalTab> createState() => _AuditoriaGlobalTabState();
}

class _AuditoriaGlobalTabState extends State<AuditoriaGlobalTab> {
  String _filtroSelecionado = '6M'; // Opções: '6M', '12M', 'ANO'

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Hive.box<LancamentoMensal>('lancamentos').listenable(),
      builder: (context, Box<LancamentoMensal> box, _) {
        final todosLancamentos = box.values
            .where((l) => !l.isDeletado)
            .toList();

        if (todosLancamentos.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.analytics_outlined, size: 48, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  "Sem dados para análise global.",
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        final dadosGrafico = _processarDadosGrafico(todosLancamentos);
        final topViloes = _processarTopViloes(todosLancamentos);

        return LayoutBuilder(
          builder: (context, constraints) {
            bool isWeb = constraints.maxWidth >= 900;

            if (isWeb) {
              // ===============================================================
              // LAYOUT WEB: COLUNAS LADO A LADO (BENTO GRID)
              // ===============================================================
              return SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ESQUERDA: Gráfico (Ganha mais espaço)
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    "Balanço Energético",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Tooltip(
                                    message:
                                        'Comparativo entre produção e consumo em todas as unidades.',
                                    child: Icon(
                                      Icons.info_outline,
                                      size: 20,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  _buildFilterChip('6 Meses', '6M'),
                                  const SizedBox(width: 8),
                                  _buildFilterChip('12 Meses', '12M'),
                                  const SizedBox(width: 8),
                                  _buildFilterChip('Este Ano', 'ANO'),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          // Gráfico estendido para Web (altura de 350px)
                          _buildGraficoContainer(dadosGrafico, 350, isWeb),
                        ],
                      ),
                    ),
                    const SizedBox(width: 32),
                    // DIREITA: Top Vilões
                    Expanded(
                      flex: 1,
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Top 3 - Maiores Faturas",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              "Referência do último mês registrado.",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 20),
                            if (topViloes.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Text(
                                  "Nenhuma fatura relevante encontrada.",
                                  style: TextStyle(color: Colors.grey),
                                ),
                              )
                            else
                              ...topViloes.map((item) => _buildVilaoCard(item)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            } else {
              // ===============================================================
              // LAYOUT MOBILE (MANTIDO EXATAMENTE IGUAL)
              // ===============================================================
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Balanço Energético",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      Tooltip(
                        message:
                            'Comparativo entre o que foi produzido e o que foi realmente consumido em todas as unidades.',
                        triggerMode: TooltipTriggerMode.tap,
                        child: Icon(
                          Icons.info_outline,
                          size: 20,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('6 Meses', '6M'),
                        const SizedBox(width: 8),
                        _buildFilterChip('12 Meses', '12M'),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                          'Este Ano (${DateTime.now().year})',
                          'ANO',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Gráfico original do Mobile (altura de 260px)
                  _buildGraficoContainer(dadosGrafico, 260, isWeb),

                  const SizedBox(height: 30),

                  const Text(
                    "Top 3 - Maiores Faturas (Último Mês)",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Onde seu dinheiro está indo embora.",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),

                  if (topViloes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        "Nenhuma fatura relevante encontrada no último mês.",
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  else
                    ...topViloes.map((item) => _buildVilaoCard(item)),

                  const SizedBox(height: 50),
                ],
              );
            }
          },
        );
      },
    );
  }

  // --- COMPONENTES VISUAIS ---

  Widget _buildGraficoContainer(
    List<Map<String, dynamic>> dadosGrafico,
    double alturaTotal,
    bool isWeb,
  ) {
    return Container(
      height: alturaTotal,
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem("Geração (Produziu)", Colors.orange),
              const SizedBox(width: 16),
              _buildLegendItem("Consumo (Gastou)", Colors.blue),
            ],
          ),
          const SizedBox(height: 20),
          // SOLUÇÃO DO RENDERFLEX: Gráfico envolto num Scroll Horizontal para evitar esmagamento no telemóvel
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                double availableHeight = constraints.maxHeight;
                double maxBarHeight = availableHeight - 45;
                if (maxBarHeight < 10) {
                  maxBarHeight = 10;
                }

                // Calcula a largura necessária para o gráfico
                // No telemóvel, cada mês ocupa pelo menos 60 pixels de largura para não esmagar.
                // Na Web, divide-se o ecrã igualmente.
                double chartWidth = isWeb
                    ? constraints.maxWidth
                    : (dadosGrafico.length * 60.0).clamp(
                        constraints.maxWidth,
                        double.infinity,
                      );

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: SizedBox(
                    width: chartWidth,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: dadosGrafico.map((mesData) {
                        return _buildBarraMes(mesData, maxBarHeight);
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
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
        if (selected) {
          setState(() {
            _filtroSelecionado = value;
          });
        }
      },
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
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildBarraMes(Map<String, dynamic> data, double maxHeight) {
    double maiorValorDoDataset = 5000;
    if (data['geracao'] > maiorValorDoDataset) {
      maiorValorDoDataset = data['geracao'];
    }
    if (data['consumo'] > maiorValorDoDataset) {
      maiorValorDoDataset = data['consumo'];
    }
    if (maiorValorDoDataset == 0) maiorValorDoDataset = 1;

    double hLaranja = (data['geracao'] / maiorValorDoDataset) * maxHeight;
    double hAzul = (data['consumo'] / maiorValorDoDataset) * maxHeight;

    if (hLaranja < 4 && data['geracao'] > 0) hLaranja = 4;
    if (hAzul < 4 && data['consumo'] > 0) hAzul = 4;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              mainAxisAlignment:
                  MainAxisAlignment.end, // Garante que alinhem pelo fundo
              children: [
                if (data['geracao'] > 0)
                  Text(
                    NumberFormat.compact().format(data['geracao']),
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                const SizedBox(height: 2),
                Container(
                  width: 12,
                  height: hLaranja,
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            Column(
              mainAxisAlignment:
                  MainAxisAlignment.end, // Garante que alinhem pelo fundo
              children: [
                if (data['consumo'] > 0)
                  Text(
                    NumberFormat.compact().format(data['consumo']),
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                const SizedBox(height: 2),
                Container(
                  width: 12,
                  height: hAzul,
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          data['mes'],
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.black54,
          ),
        ),
      ],
    );
  }

  Widget _buildVilaoCard(Map<String, dynamic> item) {
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    int rank = item['rank'];
    Color corRank = rank == 1
        ? Colors.red
        : (rank == 2 ? Colors.orange : Colors.amber);

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: corRank.withValues(alpha: 0.1),
          child: Text(
            '#$rank',
            style: TextStyle(color: corRank, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(
          item['nomeUsina'],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('Pagou ${moeda.format(item['valor'])}'),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 14,
          color: Colors.grey,
        ),
      ),
    );
  }

  // --- LÓGICA DE DADOS (MANTIDA INTACTA) ---

  List<Map<String, dynamic>> _processarDadosGrafico(
    List<LancamentoMensal> lancamentos,
  ) {
    final boxUsinas = Hive.box<Usina>('usinas');
    Map<String, Map<String, dynamic>> agrupado = {};

    for (var l in lancamentos) {
      String keySort = DateFormat('yyyyMM').format(l.dataReferencia);
      String keyDisplay = DateFormat(
        'MMM',
        'pt_BR',
      ).format(l.dataReferencia).toUpperCase();

      if (keySort.substring(0, 4) != DateTime.now().year.toString()) {
        keyDisplay = DateFormat(
          'MMM/yy',
          'pt_BR',
        ).format(l.dataReferencia).toUpperCase();
      }

      if (!agrupado.containsKey(keySort)) {
        agrupado[keySort] = {
          'display': keyDisplay,
          'geracao': 0.0,
          'consumo': 0.0,
          'date': l.dataReferencia,
        };
      }

      Usina? usina;
      try {
        usina = boxUsinas.values.firstWhere(
          (u) => u.id == l.usinaId && !u.isDeletado,
        );
      } catch (e) {
        usina = null;
      }

      if (usina != null) {
        if (usina.isGeradora) {
          agrupado[keySort]!['geracao'] += l.geracaoTotalKwh;
          double autoconsumo = l.geracaoTotalKwh - l.energiaInjetadaKwh;
          if (autoconsumo < 0) autoconsumo = 0;
          agrupado[keySort]!['consumo'] +=
              (autoconsumo + l.energiaConsumidaRedeKwh);
        } else {
          agrupado[keySort]!['consumo'] += l.energiaConsumidaRedeKwh;
        }
      }
    }

    List<Map<String, dynamic>> listaOrdenada = [];
    agrupado.forEach((key, value) {
      listaOrdenada.add({
        'key': key,
        'mes': value['display'],
        'geracao': value['geracao'],
        'consumo': value['consumo'],
        'date': value['date'],
      });
    });

    listaOrdenada.sort((a, b) => a['key'].compareTo(b['key']));

    DateTime agora = DateTime.now();
    if (_filtroSelecionado == '6M') {
      return listaOrdenada.length > 6
          ? listaOrdenada.sublist(listaOrdenada.length - 6)
          : listaOrdenada;
    } else if (_filtroSelecionado == '12M') {
      return listaOrdenada.length > 12
          ? listaOrdenada.sublist(listaOrdenada.length - 12)
          : listaOrdenada;
    } else if (_filtroSelecionado == 'ANO') {
      return listaOrdenada
          .where((item) => (item['date'] as DateTime).year == agora.year)
          .toList();
    }
    return listaOrdenada;
  }

  List<Map<String, dynamic>> _processarTopViloes(
    List<LancamentoMensal> lancamentos,
  ) {
    if (lancamentos.isEmpty) return [];

    List<LancamentoMensal> ordenados = List.from(lancamentos);
    ordenados.sort((a, b) => b.dataReferencia.compareTo(a.dataReferencia));
    DateTime ultimaData = ordenados.first.dataReferencia;

    final boxUsinas = Hive.box<Usina>('usinas');

    var doMes = ordenados.where((l) {
      bool dataOk =
          l.dataReferencia.year == ultimaData.year &&
          l.dataReferencia.month == ultimaData.month;
      if (!dataOk) return false;

      try {
        final u = boxUsinas.values.firstWhere((u) => u.id == l.usinaId);
        return !u.isDeletado;
      } catch (e) {
        return false;
      }
    }).toList();

    doMes.sort((a, b) => b.valorFaturaR.compareTo(a.valorFaturaR));

    List<Map<String, dynamic>> viloes = [];
    int contador = 1;

    for (var l in doMes.take(3)) {
      try {
        final usina = boxUsinas.values.firstWhere((u) => u.id == l.usinaId);
        if (l.valorFaturaR > 0) {
          viloes.add({
            'rank': contador,
            'nomeUsina': usina.nome,
            'valor': l.valorFaturaR,
          });
          contador++;
        }
      } catch (e) {
        // Ignora erros
      }
    }
    return viloes;
  }
}
