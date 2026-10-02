// Caminho: lib/screens/auditoria_individual_screen.dart
// Descrição: Tela de Auditoria Anual unificada ao Motor Central (DTO ProcessamentoCiclo).
// Versão: V4.0
// - ATUALIZADO: Agregação e cálculos mensais baseados em CalculadoraEnergetica.analisarCiclo.
// - MANTIDO: Gráficos de balanço, custo evitado, fluxo de créditos e exportação de PDF.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../models/usina.dart';
import '../models/lancamento.dart';
import '../utils/calculadora_energetica.dart';
import '../services/relatorio_auditoria_pdf.dart';

class AuditoriaIndividualScreen extends StatelessWidget {
  final Usina usina;

  const AuditoriaIndividualScreen({super.key, required this.usina});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Auditoria Anual', style: TextStyle(fontSize: 16)),
            Text(
              usina.nome,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Imprimir Relatório',
            onPressed: () async {
              final lancamentos = Hive.box<LancamentoMensal>('lancamentos')
                  .values
                  .where((l) => l.usinaId == usina.id && !l.isDeletado)
                  .toList();

              if (lancamentos.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Não há dados para imprimir.')),
                );
                return;
              }

              final metricas = CalculadoraEnergetica.calcularMetricasGerais(
                usina,
                lancamentos,
              );

              await RelatorioAuditoriaPdf.gerarEImprimirPdf(
                usina,
                lancamentos,
                metricas,
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: Hive.box<LancamentoMensal>('lancamentos').listenable(),
        builder: (context, Box<LancamentoMensal> box, _) {
          final lancamentos = box.values
              .where((l) => l.usinaId == usina.id && !l.isDeletado)
              .toList();

          lancamentos.sort(
            (a, b) => a.dataReferencia.compareTo(b.dataReferencia),
          );

          if (lancamentos.isEmpty) return _buildEmptyState();

          final dataFim = lancamentos.last.dataReferencia;
          final dataInicio = lancamentos.first.dataReferencia;
          final String intervaloFormatado =
              "${DateFormat('MMM yyyy', 'pt_BR').format(dataInicio)}  ➔  ${DateFormat('MMM yyyy', 'pt_BR').format(dataFim)}";

          final metricas = CalculadoraEnergetica.calcularMetricasGerais(
            usina,
            lancamentos,
          );

          Map<String, Map<String, dynamic>> dadosMensais = {};

          for (int i = 0; i < lancamentos.length; i++) {
            var l = lancamentos[i];
            var anterior = (i > 0) ? lancamentos[i - 1] : null;

            // ★ INTEGRAÇÃO COM O MOTOR CENTRAL (DTO)
            ProcessamentoCiclo ciclo = CalculadoraEnergetica.analisarCiclo(
              usina,
              l,
              anterior: anterior,
            );

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

            double custoProjetado = l.valorFaturaR + ciclo.economiaTotalReais;

            if (usina.isGeradora) {
              dadosMensais[key]!['geracao'] += ciclo.geracaoTotal;
            }

            dadosMensais[key]!['consumo'] += ciclo.consumoRealLocal;
            dadosMensais[key]!['custo'] += l.valorFaturaR;
            dadosMensais[key]!['custoProjetado'] += custoProjetado;
          }

          List<Map<String, dynamic>> graficoOrdenado = dadosMensais.values
              .toList();
          graficoOrdenado.sort(
            (a, b) => (a['date'] as DateTime).compareTo(b['date']),
          );

          if (graficoOrdenado.length > 12) {
            graficoOrdenado = graficoOrdenado.sublist(
              graficoOrdenado.length - 12,
            );
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    intervaloFormatado.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildResumoCard(metricas, lancamentos.length),

              const SizedBox(height: 16),
              _buildBalancoLinhasCard(graficoOrdenado),
              const SizedBox(height: 16),
              _buildFinanceiroCard(graficoOrdenado),
              const SizedBox(height: 16),
              _buildFluxoCreditosSection(lancamentos),
              const SizedBox(height: 24),
              const Text(
                "Detalhamento Mensal (Fluxo de Abatimento)",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                ),
              ),
              const SizedBox(height: 10),
              ...lancamentos.reversed.map(
                (l) => _buildMesAuditoriaCard(l, usina),
              ),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() =>
      const Center(child: Text("Sem lançamentos para auditar."));

  Widget _buildResumoCard(MetricasGerais metricas, int totalMeses) {
    final numero = NumberFormat.decimalPattern('pt_BR');
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    String labelMedia = usina.isGeradora
        ? 'Média Geração'
        : 'Média Recebimento';
    double valorMedia = usina.isGeradora
        ? metricas.mediaGeracao3Meses
        : (metricas.totalInjetadoKwh / totalMeses);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blueGrey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildInfoTile(
                usina.isGeradora ? 'Total Gerado' : 'Total Recebido',
                '${numero.format(usina.isGeradora ? metricas.totalGeradoKwh : metricas.totalInjetadoKwh)} kWh',
              ),
              _buildInfoTile(
                'Economia Total',
                moeda.format(metricas.valorTotalEconomizadoR),
                isGreen: true,
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildInfoTile(
                labelMedia,
                '${numero.format(valorMedia)} kWh/mês',
              ),
              _buildInfoTile(
                'Saldo Atual',
                '${numero.format(metricas.saldoCreditosEstimado)} kWh',
                isBold: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFluxoCreditosSection(
    List<LancamentoMensal> lancamentosAuditados,
  ) {
    final boxUsinas = Hive.box<Usina>('usinas');
    final boxLancamentos = Hive.box<LancamentoMensal>('lancamentos');
    final numero = NumberFormat.decimalPattern('pt_BR');
    List<Widget> tiles = [];

    if (usina.isGeradora) {
      Set<String> filhasIdsUnicas = usina.beneficiarias
          .map((b) => b.idUsinaFilha)
          .toSet();

      for (String idFilha in filhasIdsUnicas) {
        double totalRealRecebido = 0;
        double totalTeoricoCalculado = 0;

        String nomeFilha = usina.beneficiarias
            .firstWhere((b) => b.idUsinaFilha == idFilha)
            .nome;

        for (var lGeradora in lancamentosAuditados) {
          try {
            final faturaFilhaMesmoMes = boxLancamentos.values.firstWhere(
              (lf) =>
                  lf.usinaId == idFilha &&
                  !lf.isDeletado &&
                  lf.dataReferencia.year == lGeradora.dataReferencia.year &&
                  lf.dataReferencia.month == lGeradora.dataReferencia.month,
            );

            if ((faturaFilhaMesmoMes.creditosRecebidosDeTerceiros ?? 0) > 0) {
              totalRealRecebido +=
                  faturaFilhaMesmoMes.creditosRecebidosDeTerceiros!;
            } else if (faturaFilhaMesmoMes.energiaInjetadaKwh > 0) {
              totalRealRecebido += faturaFilhaMesmoMes.energiaInjetadaKwh;
            }
          } catch (e) {
            debugPrint('[V3.2] Sem fatura da filha no mesmo mês: $e');
          }

          totalTeoricoCalculado +=
              CalculadoraEnergetica.obterCreditoRepassadoParaFilha(
                usina,
                lGeradora,
                idFilha,
              );
        }

        bool exibindoTerico = totalRealRecebido <= 0;

        tiles.add(
          _buildFluxoTile(
            nomeFilha,
            exibindoTerico ? totalTeoricoCalculado : totalRealRecebido,
            Colors.orange,
            numero,
            isTeorico: exibindoTerico,
          ),
        );
      }
    } else {
      double totalTeoricoGlobal = 0;
      double totalRealGlobal = 0;
      bool temDadoReal = false;

      for (var lFilha in lancamentosAuditados) {
        if ((lFilha.creditosRecebidosDeTerceiros ?? 0) > 0) {
          totalRealGlobal += lFilha.creditosRecebidosDeTerceiros!;
          temDadoReal = true;
        }
      }

      final maes = boxUsinas.values.where(
        (u) =>
            u.isGeradora &&
            !u.isDeletado &&
            u.beneficiarias.any((b) => b.idUsinaFilha == usina.id),
      );

      for (var mae in maes) {
        double totalTeoricoDestaMae = 0;

        final lancsMae = boxLancamentos.values
            .where((l) => l.usinaId == mae.id && !l.isDeletado)
            .toList();

        for (var lFilha in lancamentosAuditados) {
          try {
            final faturaDaMaeNoMesmoMes = lancsMae.firstWhere(
              (lm) =>
                  lm.dataReferencia.year == lFilha.dataReferencia.year &&
                  lm.dataReferencia.month == lFilha.dataReferencia.month,
            );

            totalTeoricoDestaMae +=
                CalculadoraEnergetica.obterCreditoRepassadoParaFilha(
                  mae,
                  faturaDaMaeNoMesmoMes,
                  usina.id,
                );
          } catch (e) {
            debugPrint('[V3.2] Mãe sem fatura no mês: $e');
          }
        }

        totalTeoricoGlobal += totalTeoricoDestaMae;

        tiles.add(
          _buildFluxoTile(
            mae.nome,
            totalTeoricoDestaMae,
            Colors.blue,
            numero,
            isTeorico: true,
          ),
        );
      }

      if (temDadoReal && (totalTeoricoGlobal - totalRealGlobal) > 1.0) {
        tiles.add(
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange.shade800,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Retenção da Concessionária",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  "Era esperado um crédito de ${numero.format(totalTeoricoGlobal)} kWh, mas a concessionária creditou apenas ${numero.format(totalRealGlobal)} kWh reais na fatura.",
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Diferença retida: ${numero.format(totalTeoricoGlobal - totalRealGlobal)} kWh",
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    if (tiles.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(
          usina.isGeradora
              ? "Destino dos Créditos (Consolidado, Taxas Variáveis)"
              : "Origem dos Créditos (Consolidado, Taxas Variáveis)",
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        ...tiles,
      ],
    );
  }

  Widget _buildFluxoTile(
    String nome,
    double valor,
    Color cor,
    NumberFormat numero, {
    bool isTeorico = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                nome,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: isTeorico
                    ? 'Valor teórico calculado (dado real de recebimento não preenchido). As taxas de rateio variaram durante o ano.'
                    : 'Valor consolidado. As taxas de rateio variaram durante o ano.',
                triggerMode: TooltipTriggerMode.tap,
                child: Icon(
                  isTeorico ? Icons.info_outline : Icons.help_outline,
                  size: 14,
                  color: cor.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          Text(
            "${numero.format(valor)} kWh",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: cor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMesAuditoriaCard(LancamentoMensal l, Usina usina) {
    final numero = NumberFormat.decimalPattern('pt_BR');
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    // Usa o motor central para pegar o laudo unificado do mês
    ProcessamentoCiclo ciclo = CalculadoraEnergetica.analisarCiclo(usina, l);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat(
                    'MMM yyyy',
                    'pt_BR',
                  ).format(l.dataReferencia).toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  moeda.format(l.valorFaturaR),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: l.valorFaturaR < 100 ? Colors.green : Colors.black87,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMiniStat(
                  usina.isGeradora ? "Geração Total" : "Consumo Total",
                  "${numero.format(usina.isGeradora ? ciclo.geracaoTotal : ciclo.consumoRealLocal)} kWh",
                ),
                const Icon(Icons.remove, size: 14, color: Colors.grey),
                _buildMiniStat(
                  usina.isGeradora ? "Consumo Local" : "Crédito Usado",
                  "${numero.format(usina.isGeradora ? ciclo.consumoRealLocal : (ciclo.totalCreditosDisponiveisNoMes > ciclo.consumoRealLocal ? ciclo.consumoRealLocal : ciclo.totalCreditosDisponiveisNoMes))} kWh",
                ),
                const Icon(Icons.drag_handle, size: 14, color: Colors.grey),
                _buildMiniStat(
                  usina.isGeradora ? "Exportado" : "Sobrou/Faltou",
                  "${numero.format(usina.isGeradora ? ciclo.injetadoNaRede : ciclo.sobraFisicaDoMes)} kWh",
                  color: (usina.isGeradora || ciclo.sobraFisicaDoMes >= 0)
                      ? Colors.green
                      : Colors.red,
                ),
              ],
            ),
            if (!usina.isGeradora) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Total de Créditos Recebidos (Fatura):",
                      style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                    ),
                    Text(
                      "${numero.format(ciclo.totalCreditosDisponiveisNoMes)} kWh",
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, {Color? color}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: color ?? Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoTile(
    String label,
    String value, {
    bool isGreen = false,
    bool isBold = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isGreen
                ? Colors.green
                : (isBold ? Colors.blue : Colors.black87),
          ),
        ),
      ],
    );
  }

  Widget _buildBalancoLinhasCard(List<Map<String, dynamic>> dados) {
    return _buildBaseCard(
      titulo: usina.isGeradora ? "Balanço Energético" : "Histórico de Consumo",
      icone: Icons.analytics_outlined,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (usina.isGeradora) ...[
                _buildLegendItem("Geração KWh", Colors.orange),
                const SizedBox(width: 16),
              ],
              _buildLegendItem("Consumo Real KWh", Colors.blue),
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
                  usina.isGeradora ? Colors.orange : Colors.transparent,
                  Colors.blue,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBaseCard({
    required String titulo,
    required IconData icone,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
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

  Widget _buildFinanceiroCard(List<Map<String, dynamic>> dados) {
    return _buildBaseCard(
      titulo: "Custo Evitado (Economia Isolada)",
      icone: Icons.savings_outlined,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem(
                "Sem Solar (Custo Projetado)",
                Colors.grey.shade300,
              ),
              const SizedBox(width: 16),
              _buildLegendItem("Com Solar (Custo Real)", Colors.green),
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
                color: Colors.grey.shade400,
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
                  color: Colors.grey.shade200,
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

    if (colorGeracao != Colors.transparent) {
      _drawPath(
        canvas,
        size,
        pointsG,
        colorGeracao,
        chartHeight,
        paddingTop,
        chartBottomY,
      );
    }

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

      if (colorGeracao != Colors.transparent && dados[i]['geracao'] > 0) {
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
