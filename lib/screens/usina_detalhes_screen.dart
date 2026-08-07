// Caminho: lib/screens/usina_detalhes_screen.dart
// Descrição: Dashboard de Performance da Usina (Com Auditoria Visível e Fonte Única de Verdade).

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../models/usina.dart';
import '../models/lancamento.dart';
import '../utils/calculadora_energetica.dart';
import '../utils/app_feedback.dart';
import '../services/sync_queue_service.dart';
import 'lancamento_mensal_screen.dart';
import 'cadastro_usina_screen.dart';

class UsinaDetalhesScreen extends StatefulWidget {
  final Usina usina;

  const UsinaDetalhesScreen({super.key, required this.usina});

  @override
  State<UsinaDetalhesScreen> createState() => _UsinaDetalhesScreenState();
}

class _UsinaDetalhesScreenState extends State<UsinaDetalhesScreen> {
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _numero = NumberFormat.decimalPattern('pt_BR');

  // --- FUNÇÃO: CALIBRAR INVERSOR ---
  void _mostrarBottomSheetCalibracao(
    double totalGeradoAtual,
    int quantidadeMeses,
  ) {
    final TextEditingController controller = TextEditingController();
    bool isCalibrando = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
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
                        Icon(Icons.tune, color: Colors.deepOrange),
                        SizedBox(width: 8),
                        Text(
                          'Calibrar Inversor',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'A soma registrada no app é ${_numero.format(totalGeradoAtual)} kWh.\n\nQual é a leitura total no visor do Inversor hoje?',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Leitura Atual (kWh)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        suffixText: 'kWh',
                      ),
                      enabled: !isCalibrando,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'A diferença será dividida pelos $quantidadeMeses meses já registrados, atualizando o seu histórico e gráficos suavemente.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
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
                        onPressed: isCalibrando
                            ? null
                            : () async {
                                String valStr = controller.text
                                    .replaceAll('.', '')
                                    .replaceAll(',', '.');
                                double novaLeitura =
                                    double.tryParse(valStr) ?? 0.0;

                                if (novaLeitura <= totalGeradoAtual) {
                                  AppFeedback.show(
                                    context,
                                    'A leitura deve ser maior que o total já registrado.',
                                    isError: true,
                                  );
                                  return;
                                }

                                setModalState(() {
                                  isCalibrando = true;
                                });

                                double diferenca =
                                    novaLeitura - totalGeradoAtual;
                                double acressimoPorMes =
                                    diferenca / quantidadeMeses;

                                final box = Hive.box<LancamentoMensal>(
                                  'lancamentos',
                                );
                                final lancamentosDaUsina = box.values
                                    .where(
                                      (l) =>
                                          l.usinaId == widget.usina.id &&
                                          !l.isDeletado,
                                    )
                                    .toList();

                                final agora = DateTime.now();

                                for (var lancamento in lancamentosDaUsina) {
                                  lancamento.geracaoTotalKwh += acressimoPorMes;
                                  lancamento.ultimaModificacao = agora;
                                  await lancamento.save();
                                  await SyncQueueService.enqueue(
                                    'lancamentos',
                                    lancamento.id,
                                  );
                                }

                                if (context.mounted) {
                                  Navigator.pop(context);
                                  AppFeedback.show(
                                    context,
                                    'Inversor calibrado! O histórico foi atualizado.',
                                  );
                                  setState(() {});
                                }
                              },
                        child: isCalibrando
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'CALIBRAR SISTEMA',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!isCalibrando)
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            'Cancelar',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- FUNÇÃO: HISTÓRICO EXPANDIDO ---
  void _mostrarHistoricoCompleto(
    BuildContext context,
    List<LancamentoMensal> todosLancamentos,
    double totalDesvioGeral,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.90,
          decoration: const BoxDecoration(
            color: Color(0xFFF5F7FA),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Histórico Completo',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  itemCount: todosLancamentos.length,
                  itemBuilder: (context, index) {
                    LancamentoMensal lanc = todosLancamentos[index];
                    LancamentoMensal? lancAnterior;
                    if (index + 1 < todosLancamentos.length) {
                      lancAnterior = todosLancamentos[index + 1];
                    }
                    double desvio = CalculadoraEnergetica.calcularDesvioDoMes(
                      widget.usina,
                      lanc,
                      lancAnterior,
                    );

                    // Adiciona o desvio de repasse da Mãe vs Filha para mostrar o ícone de alerta
                    if (!widget.usina.isGeradora) {
                      double teoricoMes = 0;
                      final boxUsinas = Hive.box<Usina>('usinas');
                      final boxLancamentos = Hive.box<LancamentoMensal>(
                        'lancamentos',
                      );
                      final maes = boxUsinas.values.where(
                        (u) =>
                            u.isGeradora &&
                            !u.isDeletado &&
                            u.beneficiarias.any(
                              (b) => b.idUsinaFilha == widget.usina.id,
                            ),
                      );
                      for (var mae in maes) {
                        try {
                          final lancMae = boxLancamentos.values.firstWhere(
                            (lm) =>
                                lm.usinaId == mae.id &&
                                !lm.isDeletado &&
                                lm.dataReferencia.year ==
                                    lanc.dataReferencia.year &&
                                lm.dataReferencia.month ==
                                    lanc.dataReferencia.month,
                          );
                          teoricoMes +=
                              CalculadoraEnergetica.obterCreditoRepassadoParaFilha(
                                mae,
                                lancMae,
                                widget.usina.id,
                              );
                        } catch (_) {}
                      }
                      double realMes =
                          (lanc.creditosRecebidosDeTerceiros != null &&
                              lanc.creditosRecebidosDeTerceiros! > 0)
                          ? lanc.creditosRecebidosDeTerceiros!
                          : lanc.energiaInjetadaKwh;

                      if (teoricoMes > realMes &&
                          (teoricoMes - realMes) > 1.0) {
                        desvio += (teoricoMes - realMes);
                      }
                    }

                    return _buildLancamentoCard(lanc, desvio);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.black87),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      CadastroUsinaScreen(usinaParaEditar: widget.usina),
                ),
              ).then((_) => setState(() {}));
            },
          ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: Hive.box<LancamentoMensal>('lancamentos').listenable(),
        builder: (context, Box<LancamentoMensal> box, _) {
          final lancamentos = box.values
              .where((l) => l.usinaId == widget.usina.id && !l.isDeletado)
              .toList();

          final lancamentosOrdenados = List<LancamentoMensal>.from(lancamentos);
          lancamentosOrdenados.sort(
            (a, b) => b.dataReferencia.compareTo(a.dataReferencia),
          );

          final ultimos6Lancamentos = lancamentosOrdenados.take(6).toList();

          final metricas = CalculadoraEnergetica.calcularMetricasGerais(
            widget.usina,
            lancamentos,
          );

          double totalConsumidoDaRede = lancamentos.fold(
            0.0,
            (sum, l) => sum + l.energiaConsumidaRedeKwh,
          );

          double retidoConcessionaria = 0;
          for (var l in lancamentos) {
            final resumo = CalculadoraEnergetica.gerarResumoMesOficial(
              widget.usina,
              l,
            );
            retidoConcessionaria += resumo.taxaMinimaRetida;
          }

          // RESTAURAÇÃO: Cálculo Global de Créditos Desviados para Beneficiárias
          double totalDesvioGeral = metricas.totalCreditosDesviados;

          if (!widget.usina.isGeradora) {
            final boxUsinas = Hive.box<Usina>('usinas');
            final boxLancamentos = Hive.box<LancamentoMensal>('lancamentos');
            final maes = boxUsinas.values.where(
              (u) =>
                  u.isGeradora &&
                  !u.isDeletado &&
                  u.beneficiarias.any((b) => b.idUsinaFilha == widget.usina.id),
            );

            for (var l in lancamentos) {
              double teoricoMes = 0;
              for (var mae in maes) {
                try {
                  final lancMae = boxLancamentos.values.firstWhere(
                    (lm) =>
                        lm.usinaId == mae.id &&
                        !lm.isDeletado &&
                        lm.dataReferencia.year == l.dataReferencia.year &&
                        lm.dataReferencia.month == l.dataReferencia.month,
                  );
                  teoricoMes +=
                      CalculadoraEnergetica.obterCreditoRepassadoParaFilha(
                        mae,
                        lancMae,
                        widget.usina.id,
                      );
                } catch (_) {}
              }
              double realMes =
                  (l.creditosRecebidosDeTerceiros != null &&
                      l.creditosRecebidosDeTerceiros! > 0)
                  ? l.creditosRecebidosDeTerceiros!
                  : l.energiaInjetadaKwh;

              if (teoricoMes > realMes && (teoricoMes - realMes) > 1.0) {
                totalDesvioGeral += (teoricoMes - realMes);
              }
            }
          }

          Map<String, dynamic> saudeSistema = {};
          double producaoIdeal = 0;
          if (widget.usina.isGeradora) {
            saudeSistema = CalculadoraEnergetica.calcularSaudeSistema(
              widget.usina,
              lancamentos,
            );
            producaoIdeal = CalculadoraEnergetica.estimarProducaoIdealMensal(
              widget.usina,
            );
          }

          LancamentoMensal? ultimoLancamento;
          double ultimoMesProducaoOuRecebido = 0;
          double ultimoMesConsumoReal = 0;
          String nomeUltimoMes = "---";

          if (lancamentosOrdenados.isNotEmpty) {
            final ultimo = lancamentosOrdenados.first;
            ultimoLancamento = ultimo;

            nomeUltimoMes = DateFormat(
              'MMMM yyyy',
              'pt_BR',
            ).format(ultimo.dataReferencia).toUpperCase();

            final resumoUltimo = CalculadoraEnergetica.gerarResumoMesOficial(
              widget.usina,
              ultimo,
            );
            ultimoMesProducaoOuRecebido = widget.usina.isGeradora
                ? resumoUltimo.geracaoTotal
                : resumoUltimo.injetadoOuRecebido;
            ultimoMesConsumoReal = resumoUltimo.consumoRealLocal;
          }

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.usina.nome,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                      color: Colors.black87,
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        widget.usina.isGeradora
                            ? Icons.wb_sunny
                            : Icons.home_work,
                        size: 14,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'UC: ${widget.usina.id} • ${widget.usina.isGeradora ? "Geradora" : "Beneficiária"}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              _buildPerfilConsumoCard(
                widget.usina,
                metricas.mediaConsumo3Meses,
              ),
              const SizedBox(height: 20),

              if (widget.usina.isGeradora) ...[
                _buildDadosTecnicosCard(
                  widget.usina,
                  metricas.totalGeradoKwh,
                  lancamentos.length,
                ),
                const SizedBox(height: 20),
              ],

              if (ultimoLancamento != null)
                _buildCardPerformanceMensal(
                  nomeUltimoMes,
                  ultimoMesProducaoOuRecebido,
                  ultimoMesConsumoReal,
                  ultimoLancamento,
                ),
              const SizedBox(height: 10),

              if (widget.usina.isGeradora && saudeSistema.isNotEmpty) ...[
                const Text(
                  'SAÚDE E CAPACIDADE',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                    fontSize: 12,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 10),
                _buildCardSaudeSistema(saudeSistema, producaoIdeal),
                const SizedBox(height: 24),
              ],
              const Text(
                'ACUMULADO HISTÓRICO',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                  fontSize: 12,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 10),
              _buildTotalEconomiaCard(metricas.valorTotalEconomizadoR),
              const SizedBox(height: 12),
              _buildSaldoCreditosCard(metricas.saldoCreditosEstimado),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.orange.shade500,
                      Colors.deepOrange.shade600,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.usina.isGeradora
                          ? 'Total Exportado'
                          : 'Total Recebido (Créditos)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${_numero.format(metricas.totalInjetadoKwh)} kWh',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              if (widget.usina.totalInvestido > 0 &&
                  widget.usina.isGeradora) ...[
                _buildCardROI(
                  metricas.percentualRoi,
                  widget.usina.totalInvestido,
                  metricas.valorTotalEconomizadoR,
                ),
                const SizedBox(height: 16),
              ],

              if (widget.usina.isGeradora) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildMetricTile(
                        'Produção',
                        _numero.format(metricas.totalGeradoKwh),
                        Icons.solar_power,
                        Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMetricTile(
                        'Autoconsumo',
                        _numero.format(metricas.totalAutoconsumoKwh),
                        Icons.home_filled,
                        Colors.purple,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMetricTile(
                        'Total Rede',
                        _numero.format(totalConsumidoDaRede),
                        Icons.electrical_services,
                        Colors.redAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              // RESTAURAÇÃO: Card de Perdas e Retenções movido para FORA do bloco isGeradora!
              // Agora a Roberta (Beneficiária) também verá os créditos que foram desviados.
              if (retidoConcessionaria > 0 || totalDesvioGeral > 0) ...[
                _buildPerdasERetencoesCard(
                  retidoConcessionaria,
                  totalDesvioGeral,
                ),
                const SizedBox(height: 12),
              ],

              const SizedBox(height: 25),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'HISTÓRICO RECENTE',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    '${lancamentosOrdenados.length} no total',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              if (lancamentosOrdenados.isEmpty)
                _buildEmptyState()
              else ...[
                ...ultimos6Lancamentos.map((lanc) {
                  LancamentoMensal? lancAnterior;
                  int anteriorIdx = lancamentosOrdenados.indexOf(lanc) + 1;

                  if (anteriorIdx < lancamentosOrdenados.length) {
                    lancAnterior = lancamentosOrdenados[anteriorIdx];
                  }

                  double desvio = CalculadoraEnergetica.calcularDesvioDoMes(
                    widget.usina,
                    lanc,
                    lancAnterior,
                  );

                  // RESTAURAÇÃO: Injeta o desvio de repasse para o ícone amarelo aparecer na lista
                  if (!widget.usina.isGeradora) {
                    double teoricoMes = 0;
                    final boxUsinas = Hive.box<Usina>('usinas');
                    final boxLancamentos = Hive.box<LancamentoMensal>(
                      'lancamentos',
                    );
                    final maes = boxUsinas.values.where(
                      (u) =>
                          u.isGeradora &&
                          !u.isDeletado &&
                          u.beneficiarias.any(
                            (b) => b.idUsinaFilha == widget.usina.id,
                          ),
                    );
                    for (var mae in maes) {
                      try {
                        final lancMae = boxLancamentos.values.firstWhere(
                          (lm) =>
                              lm.usinaId == mae.id &&
                              !lm.isDeletado &&
                              lm.dataReferencia.year ==
                                  lanc.dataReferencia.year &&
                              lm.dataReferencia.month ==
                                  lanc.dataReferencia.month,
                        );
                        teoricoMes +=
                            CalculadoraEnergetica.obterCreditoRepassadoParaFilha(
                              mae,
                              lancMae,
                              widget.usina.id,
                            );
                      } catch (_) {}
                    }
                    double realMes =
                        (lanc.creditosRecebidosDeTerceiros != null &&
                            lanc.creditosRecebidosDeTerceiros! > 0)
                        ? lanc.creditosRecebidosDeTerceiros!
                        : lanc.energiaInjetadaKwh;

                    if (teoricoMes > realMes && (teoricoMes - realMes) > 1.0) {
                      desvio += (teoricoMes - realMes);
                    }
                  }

                  return _buildLancamentoCard(lanc, desvio);
                }),

                if (lancamentosOrdenados.length > 6)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: OutlinedButton(
                      onPressed: () => _mostrarHistoricoCompleto(
                        context,
                        lancamentosOrdenados,
                        totalDesvioGeral,
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Colors.deepOrange.shade200),
                      ),
                      child: const Text(
                        'VER TODO O HISTÓRICO',
                        style: TextStyle(
                          color: Colors.deepOrange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 80),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.deepOrange,
        icon: const Icon(Icons.add_chart, color: Colors.white),
        label: const Text(
          'Lançar Mês',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  LancamentoMensalScreen(usinaPreSelecionada: widget.usina),
            ),
          ).then((_) => setState(() {}));
        },
      ),
    );
  }

  void _mostrarDetalhesLancamento(
    BuildContext context,
    LancamentoMensal lancamento,
    double desvioOriginal,
  ) {
    final resumo = CalculadoraEnergetica.gerarResumoMesOficial(
      widget.usina,
      lancamento,
    );

    double totalCreditoTeorico = 0;
    List<Map<String, dynamic>> listaCreditosTeoricos = [];

    if (!widget.usina.isGeradora) {
      final boxUsinas = Hive.box<Usina>('usinas');
      final boxLanc = Hive.box<LancamentoMensal>('lancamentos');
      final maes = boxUsinas.values.where(
        (u) =>
            u.isGeradora &&
            !u.isDeletado &&
            u.beneficiarias.any((b) => b.idUsinaFilha == widget.usina.id),
      );

      for (var mae in maes) {
        try {
          final lancMae = boxLanc.values.firstWhere(
            (l) =>
                l.usinaId == mae.id &&
                !l.isDeletado &&
                l.dataReferencia.year == lancamento.dataReferencia.year &&
                l.dataReferencia.month == lancamento.dataReferencia.month,
          );

          double recebidoTeorico =
              CalculadoraEnergetica.obterCreditoRepassadoParaFilha(
                mae,
                lancMae,
                widget.usina.id,
              );

          totalCreditoTeorico += recebidoTeorico;
          listaCreditosTeoricos.add({
            'nome': mae.nome,
            'valor': recebidoTeorico,
          });
        } catch (e) {
          // Ignora erros
        }
      }
    }

    // --- CORREÇÃO DA TARIFA DE EXIBIÇÃO ---
    double tarifaExibicao = lancamento.tarifaKwh;
    if (lancamento.grupoTarifario == 'A' ||
        lancamento.modalidadeTarifaria == 'VERDE' ||
        lancamento.modalidadeTarifaria == 'AZUL') {
      if ((lancamento.tarifaTeForaPonta ?? 0) > 0) {
        tarifaExibicao =
            lancamento.tarifaTeForaPonta! +
            (lancamento.tarifaTusdForaPonta ?? 0);
      }
    } else {
      if ((lancamento.tarifaTeUnica ?? 0) > 0) {
        tarifaExibicao =
            lancamento.tarifaTeUnica! + (lancamento.tarifaTusdUnica ?? 0);
      }
    }
    if (tarifaExibicao <= 0) {
      tarifaExibicao = lancamento.tarifaKwh;
    }
    // --------------------------------------

    // RESTAURAÇÃO: Preparando a matemática do "Auditor Implacável"
    double desvioCalculado = desvioOriginal;
    double diferencaRepasse = 0.0;

    if (!widget.usina.isGeradora && listaCreditosTeoricos.isNotEmpty) {
      double repasseReal =
          (lancamento.creditosRecebidosDeTerceiros != null &&
              lancamento.creditosRecebidosDeTerceiros! > 0)
          ? lancamento.creditosRecebidosDeTerceiros!
          : lancamento.energiaInjetadaKwh;

      diferencaRepasse = totalCreditoTeorico - repasseReal;

      if (diferencaRepasse > 1.0) {
        desvioCalculado += diferencaRepasse;
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.90,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      DateFormat(
                        'MMMM yyyy',
                        'pt_BR',
                      ).format(lancamento.dataReferencia).toUpperCase(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () async {
                        Navigator.pop(context);
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LancamentoMensalScreen(
                              usinaPreSelecionada: widget.usina,
                              lancamentoParaEditar: lancamento,
                            ),
                          ),
                        ).then((_) => setState(() {}));
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.usina.isGeradora) ...[
                        _buildSectionHeader(
                          'Produção (Inversor)',
                          Icons.solar_power,
                        ),
                        _buildDetailRow(
                          'Geração Total',
                          '${_numero.format(resumo.geracaoTotal)} kWh',
                          boldValue: true,
                        ),
                        _buildDetailRow(
                          'Autoconsumo',
                          '${_numero.format(resumo.autoconsumo)} kWh',
                          colorValue: Colors.purple,
                        ),
                        if (lancamento.leituraInversor != null &&
                            lancamento.leituraInversor! > 0)
                          _buildDetailRow(
                            'Leitura (Fim do Mês)',
                            '${_numero.format(lancamento.leituraInversor)} kWh',
                            isSubtle: true,
                          ),
                        const Divider(height: 24),
                      ],
                      _buildSectionHeader(
                        'Distribuição dos Créditos',
                        Icons.share,
                      ),
                      if (widget.usina.isGeradora) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total Injetado na Rede',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                              Text(
                                '${_numero.format(lancamento.energiaInjetadaKwh)} kWh',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (widget.usina.beneficiarias.isNotEmpty)
                          ...widget.usina.beneficiarias.map((b) {
                            double enviadoParaEsta =
                                CalculadoraEnergetica.obterCreditoRepassadoParaFilha(
                                  widget.usina,
                                  lancamento,
                                  b.idUsinaFilha,
                                );

                            if (enviadoParaEsta == 0 && b.percentual > 0) {
                              return const SizedBox.shrink();
                            }

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.arrow_forward_rounded,
                                          size: 14,
                                          color: Colors.green.shade600,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            '${b.nome} (${b.percentual.toStringAsFixed(0)}%)',
                                            style: TextStyle(
                                              color: Colors.grey.shade800,
                                              fontSize: 13,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${_numero.format(enviadoParaEsta)} kWh',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Consumo Real (Medidor)',
                                    style: TextStyle(color: Colors.black87),
                                  ),
                                  Text(
                                    '${_numero.format(resumo.consumoRealLocal)} kWh',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Crédito Aplicado (Fatura)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                  Text(
                                    '- ${_numero.format(resumo.injetadoOuRecebido)} kWh',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                      const Divider(height: 24),
                      _buildSectionHeader(
                        'Consumo e Fatura',
                        Icons.receipt_long,
                      ),

                      // RESTAURAÇÃO: Exibição Mista de Créditos da Usina Mãe (Mostra a origem real e alerta o desvio)
                      if (!widget.usina.isGeradora) ...[
                        Builder(
                          builder: (context) {
                            String nomesMaes = listaCreditosTeoricos
                                .map((c) => c['nome'])
                                .join(', ');
                            String labelRecebidoTerceiros = nomesMaes.isNotEmpty
                                ? 'Recebido de Terceiros ($nomesMaes)'
                                : 'Recebido de Terceiros (Usina Mãe)';

                            double repasseReal =
                                (lancamento.creditosRecebidosDeTerceiros !=
                                        null &&
                                    lancamento.creditosRecebidosDeTerceiros! >
                                        0)
                                ? lancamento.creditosRecebidosDeTerceiros!
                                : lancamento.energiaInjetadaKwh;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (lancamento.energiaInjetadaKwh > 0 &&
                                    lancamento.creditosRecebidosDeTerceiros !=
                                        null &&
                                    lancamento.creditosRecebidosDeTerceiros! >
                                        0)
                                  _buildDetailRow(
                                    'Geração Local (Injetada)',
                                    '${_numero.format(lancamento.energiaInjetadaKwh)} kWh',
                                    isSubtle: true,
                                  ),
                                _buildDetailRow(
                                  labelRecebidoTerceiros,
                                  '${_numero.format(repasseReal)} kWh',
                                  colorValue: Colors.blue,
                                ),
                                _buildDetailRow(
                                  'Crédito Total Disponível',
                                  '${_numero.format(resumo.injetadoOuRecebido)} kWh',
                                  boldValue: true,
                                  colorValue: Colors.green,
                                ),
                                const Divider(
                                  height: 16,
                                  indent: 20,
                                  endIndent: 20,
                                ),

                                if (listaCreditosTeoricos.isNotEmpty &&
                                    diferencaRepasse > 1.0) ...[
                                  const Padding(
                                    padding: EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      'Auditoria de Repasse (Mãe vs Filha):',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                  ...listaCreditosTeoricos.map(
                                    (c) => _buildDetailRow(
                                      'Enviado por ${c['nome']}',
                                      '${_numero.format(c['valor'])} kWh',
                                      colorValue: Colors.blueGrey,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildDetailRow(
                                    'Total Teórico (Seu Direito)',
                                    '${_numero.format(totalCreditoTeorico)} kWh',
                                    boldValue: true,
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 8,
                                      bottom: 8,
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.warning_amber_rounded,
                                          color: Colors.orange,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            'Diferença (Perda/Retenção): ${_numero.format(diferencaRepasse)} kWh',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.orange.shade800,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            textAlign: TextAlign.right,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Divider(
                                    height: 16,
                                    indent: 20,
                                    endIndent: 20,
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ],

                      if (widget.usina.isGeradora)
                        _buildDetailRow(
                          'Consumo Total do Local',
                          '${_numero.format(resumo.consumoRealLocal)} kWh',
                          boldValue: true,
                        ),
                      _buildDetailRow(
                        !widget.usina.isGeradora
                            ? 'Da Concessionária (Rede)'
                            : 'Da Concessionária (Rede)',
                        '${_numero.format(resumo.consumidoDaRede)} kWh',
                        colorValue: Colors.red,
                      ),
                      if (lancamento.custoDemandaR > 0) ...[
                        const SizedBox(height: 4),
                        _buildDetailRow(
                          'Demanda Contratada / Fixos',
                          _moeda.format(lancamento.custoDemandaR),
                          colorValue: Colors.orange.shade800,
                          isSubtle: false,
                        ),
                      ],
                      const SizedBox(height: 8),
                      _buildDetailRow(
                        'Tarifa Aplicada',
                        _moeda.format(tarifaExibicao),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Valor Pago:',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.black54,
                              ),
                            ),
                            Text(
                              _moeda.format(lancamento.valorFaturaR),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 30),
                      const Divider(height: 30),
                      _buildSectionHeader(
                        'Balanço Financeiro (Energia)',
                        Icons.balance,
                      ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: resumo.sobraFisicaDoMes >= 0
                              ? Colors.green.shade50
                              : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: resumo.sobraFisicaDoMes >= 0
                                ? Colors.green.shade200
                                : Colors.red.shade200,
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  resumo.sobraFisicaDoMes >= 0
                                      ? 'Saldo do Mês (Sobrou)'
                                      : 'Déficit (Faltou)',
                                  style: TextStyle(
                                    color: resumo.sobraFisicaDoMes >= 0
                                        ? Colors.green.shade800
                                        : Colors.red.shade800,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${resumo.sobraFisicaDoMes >= 0 ? "+" : ""}${_numero.format(resumo.sobraFisicaDoMes)} kWh',
                                  style: TextStyle(
                                    color: resumo.sobraFisicaDoMes >= 0
                                        ? Colors.green.shade800
                                        : Colors.red.shade800,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            if (resumo.sobraFisicaDoMes < 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  resumo.saldoAcumuladoExibicao > 0
                                      ? "Atenção: O consumo superou os créditos recebidos. Este déficit foi abatido do seu saldo acumulado anterior."
                                      : "Atenção: O consumo superou os créditos recebidos. Como não havia saldo acumulado suficiente, a diferença foi cobrada na fatura.",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.red.shade800,
                                    fontStyle: FontStyle.italic,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            const SizedBox(height: 12),
                            Divider(
                              color: resumo.sobraFisicaDoMes >= 0
                                  ? Colors.green.shade200
                                  : Colors.red.shade200,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  resumo.isSaldoEstimado
                                      ? 'Saldo Acumulado (Estimado)'
                                      : 'Saldo Acumulado (Fatura)',
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.bold,
                                    fontStyle: resumo.isSaldoEstimado
                                        ? FontStyle.italic
                                        : FontStyle.normal,
                                  ),
                                ),
                                Text(
                                  '${_numero.format(resumo.saldoAcumuladoExibicao)} kWh',
                                  style: TextStyle(
                                    color: resumo.isSaldoEstimado
                                        ? Colors.orange.shade700
                                        : Colors.blue,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // RESTAURAÇÃO: A Grande Caixa Vermelha do "Auditor Implacável"
                      if (desvioCalculado > 0) ...[
                        const Divider(height: 30),
                        _buildSectionHeader(
                          'Auditoria de Saldo (FALHOU)',
                          Icons.policy,
                        ),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.report_problem,
                                    color: Colors.red,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Concessionária reteve créditos',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Neste mês, a matemática de créditos repassados ou do saldo acumulado não bateu. Pela matemática física, o seu saldo atualizado na fatura deveria ter somado os créditos, mas a concessionária ignorou.',
                                style: TextStyle(
                                  color: Colors.red.shade800,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _buildDetailRow(
                                'Desvio Detectado:',
                                '${_numero.format(desvioCalculado)} kWh',
                                boldValue: true,
                                colorValue: Colors.red.shade900,
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- CARTÃO DA GERADORA ---
  Widget _buildDadosTecnicosCard(
    Usina usina,
    double totalGeradoAtual,
    int qtdMeses,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.grey.withValues(alpha: 0.05), blurRadius: 15),
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
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.electrical_services,
                      color: Colors.deepOrange,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Dados do Sistema',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              if (usina.isGeradora && qtdMeses > 0)
                IconButton(
                  tooltip: 'Calibrar Inversor',
                  icon: const Icon(Icons.tune, color: Colors.blue),
                  onPressed: () =>
                      _mostrarBottomSheetCalibracao(totalGeradoAtual, qtdMeses),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _buildDetailRow(
            'Capacidade Instalada',
            '${usina.potenciaTotalPaineisKwp.toStringAsFixed(2)} kWp',
            boldValue: true,
            colorValue: Colors.black87,
          ),
          const Divider(height: 24),
          if (usina.inversores.isNotEmpty) ...[
            const Text(
              'Inversores',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            ...usina.inversores.map(
              (i) => _buildDetailRow(
                '${i.quantidade}x ${i.marca}',
                '${i.potenciaKw} kW',
                isSubtle: true,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (usina.paineis.isNotEmpty) ...[
            const Text(
              'Painéis',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            ...usina.paineis.map(
              (p) => _buildDetailRow(
                '${p.quantidade}x ${p.marca}',
                '${p.potenciaWatts} W',
                isSubtle: true,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- NOVO CARTÃO DA BENEFICIÁRIA ---
  Widget _buildPerfilConsumoCard(Usina usina, double mediaConsumo) {
    String taxaMinima = "100 kWh (Trifásico)";
    if (usina.tipo.toLowerCase().contains('monof')) {
      taxaMinima = "30 kWh (Monofásico)";
    }
    if (usina.tipo.toLowerCase().contains('bif')) {
      taxaMinima = "50 kWh (Bifásico)";
    }

    // --- NOVA LÓGICA: BUSCA REVERSA PARA BENEFICIÁRIAS (Sem depender de "tipo") ---
    List<Map<String, dynamic>> usinasMaes = [];
    final boxUsinas = Hive.box<Usina>('usinas');

    // Busca todas as geradoras que têm ESTA unidade na lista de repasse
    final maes = boxUsinas.values.where(
      (u) =>
          u.isGeradora &&
          !u.isDeletado &&
          u.beneficiarias.any((b) => b.idUsinaFilha.trim() == usina.id.trim()),
    );

    for (var mae in maes) {
      final vinculo = mae.beneficiarias.firstWhere(
        (b) => b.idUsinaFilha.trim() == usina.id.trim(),
      );
      usinasMaes.add({'nome': mae.nome, 'percentual': vinculo.percentual});
    }

    // Define que ela é uma beneficiária de fato SE ELA TEM UMA MÃE
    bool isBeneficiariaDeFato = usinasMaes.isNotEmpty || !usina.isGeradora;
    // ------------------------------------------------------------------------------

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.grey.withValues(alpha: 0.05), blurRadius: 15),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.home_work,
                  color: Colors.blue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Perfil da Instalação',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildDetailRow(
            'Concessionária',
            usina.concessionaria.isNotEmpty
                ? usina.concessionaria
                : 'Não informada',
            boldValue: true,
            colorValue: Colors.black87,
          ),
          const Divider(height: 24),
          _buildDetailRow(
            'Média de Consumo (3 Meses)',
            '${_numero.format(mediaConsumo)} kWh',
            colorValue: Colors.orange.shade700,
            boldValue: true,
          ),
          const SizedBox(height: 8),
          _buildDetailRow(
            'Taxa Mínima Obrigatória',
            taxaMinima,
            isSubtle: true,
          ),

          // --- NOVO BLOCO DE ORIGEM DE CRÉDITOS ---
          if (isBeneficiariaDeFato && usinasMaes.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Divider(height: 1),
            ),
            Row(
              children: [
                Icon(Icons.bolt, size: 16, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                const Text(
                  'Recebe Créditos De:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...usinasMaes.map(
              (mae) => Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 24),
                child: Row(
                  children: [
                    Icon(
                      Icons.arrow_right,
                      size: 16,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${mae['nome']} (${mae['percentual'].toStringAsFixed(0)}%)',
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          // ----------------------------------------
        ],
      ),
    );
  }

  Widget _buildCardSaudeSistema(Map<String, dynamic> dados, double ideal) {
    double ef = dados['eficiencia'];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Saúde do Ativo',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                ),
              ),
              Text(
                '${dados['anos'].toStringAsFixed(1)} anos',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: (ef / 100).clamp(0.0, 1.0),
            valueColor: AlwaysStoppedAnimation(
              ef > 90 ? Colors.green : Colors.orange,
            ),
            backgroundColor: Colors.grey.shade200,
          ),
          const SizedBox(height: 8),
          Text(
            'Eficiência: ${ef.toStringAsFixed(1)}%',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildCardPerformanceMensal(
    String mes,
    double prod,
    double cons,
    LancamentoMensal ultimoLancamento,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color.fromARGB(141, 20, 68, 0),
          width: 1.0,
        ), //
        boxShadow: [
          BoxShadow(color: Colors.grey.withValues(alpha: 0.05), blurRadius: 15),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Desempenho Recente',
                style: TextStyle(
                  color: Color.fromARGB(255, 1, 79, 248),
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                mes,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color.fromARGB(255, 1, 79, 248),
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
                    Text(
                      widget.usina.isGeradora ? 'Produziu' : 'Crédito Total',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    Text(
                      '${_numero.format(prod)} kWh',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Consumiu',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    Text(
                      '${_numero.format(cons)} kWh',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.usina.isGeradora &&
              widget.usina.beneficiarias.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1),
            ),
            const Text(
              'EXPORTADO PARA BENEFICIÁRIAS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            ...widget.usina.beneficiarias.map((b) {
              double enviadoParaEsta =
                  CalculadoraEnergetica.obterCreditoRepassadoParaFilha(
                    widget.usina,
                    ultimoLancamento,
                    b.idUsinaFilha,
                  );

              if (enviadoParaEsta == 0 && b.percentual > 0) {
                return const SizedBox.shrink();
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: Colors.green.shade600,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${b.nome} (${b.percentual.toStringAsFixed(0)}%)',
                              style: TextStyle(
                                color: Colors.grey.shade800,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${_numero.format(enviadoParaEsta)} kWh',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildTotalEconomiaCard(double v) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [Colors.green.shade600, Colors.green.shade800],
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Total Economizado',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        Text(
          _moeda.format(v),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ],
    ),
  );

  Widget _buildSaldoCreditosCard(double v) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [Colors.blue.shade600, Colors.blue.shade800],
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Saldo de Créditos',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        Text(
          v > 0 ? '${_numero.format(v)} kWh' : 'Sem saldo',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ],
    ),
  );

  Widget _buildPerdasERetencoesCard(double retido, double desviado) {
    if (retido == 0 && desviado == 0) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                color: const Color.fromARGB(255, 252, 73, 67),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Observações da Concessionária',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (retido > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Retido Total (Custo de Disponibilidade) virou crédito',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                ),
                Text(
                  '${_numero.format(retido)} kWh',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          if (desviado > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Créditos não compensados (Desvio)',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                ),
                Text(
                  '${_numero.format(desviado)} kWh',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCardROI(double p, double i, double r) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ROI: ${p.toStringAsFixed(1)}%',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: p >= 100 ? Colors.green : Colors.black87,
          ),
        ),
        Text(
          'Falta: ${_moeda.format(i - r)}',
          style: const TextStyle(color: Colors.orange),
        ),
      ],
    ),
  );

  Widget _buildMetricTile(String l, String v, IconData i, Color c) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(i, color: c, size: 20),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            v,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          l,
          style: TextStyle(color: Colors.grey[600], fontSize: 11, height: 1.1),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );

  Widget _buildLancamentoCard(LancamentoMensal item, double desvio) => Card(
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 10),
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: Colors.blue.shade100, width: 1.0),
    ),
    child: ListTile(
      onTap: () => _mostrarDetalhesLancamento(context, item, desvio),
      leading: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              DateFormat(
                'MMM',
                'pt_BR',
              ).format(item.dataReferencia).toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
                fontSize: 14,
              ),
            ),
            Text(
              DateFormat('yyyy').format(item.dataReferencia),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
      title: Text(
        '${_numero.format(!widget.usina.isGeradora ? item.energiaConsumidaRedeKwh : item.geracaoTotalKwh)} kWh',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (desvio > 0)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.warning_amber_rounded, color: Colors.red),
            ),
          Text(
            _moeda.format(item.valorFaturaR),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.redAccent,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildSectionHeader(String t, IconData i) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Icon(i, size: 18, color: Colors.deepOrange),
        const SizedBox(width: 8),
        Text(
          t,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey,
          ),
        ),
      ],
    ),
  );

  Widget _buildDetailRow(
    String l,
    String v, {
    bool boldValue = false,
    Color? colorValue,
    bool isSubtle = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          l,
          style: TextStyle(
            color: isSubtle ? Colors.grey : Colors.black54,
            fontSize: isSubtle ? 13 : 14,
          ),
        ),
        Text(
          v,
          style: TextStyle(
            fontWeight: boldValue ? FontWeight.bold : FontWeight.normal,
            color: isSubtle ? Colors.grey : (colorValue ?? Colors.black87),
            fontSize: 15,
          ),
        ),
      ],
    ),
  );

  Widget _buildEmptyState() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 30),
    child: Center(
      child: Text(
        "Sem dados registrados.",
        style: TextStyle(color: Colors.grey),
      ),
    ),
  );
}
