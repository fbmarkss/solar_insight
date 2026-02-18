// Caminho: lib/screens/usina_detalhes_screen.dart
// Descrição: Dashboard de Performance da Usina.
// ATUALIZAÇÃO: Card dinâmico (Dados do Sistema vs Perfil de Consumo).

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
                    return _buildLancamentoCard(todosLancamentos[index]);
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

          double creditosUsados =
              metricas.totalInjetadoKwh - metricas.saldoCreditosEstimado;
          double retidoConcessionaria = totalConsumidoDaRede - creditosUsados;
          if (retidoConcessionaria < 0) retidoConcessionaria = 0;

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

            if (widget.usina.isGeradora) {
              ultimoMesProducaoOuRecebido = ultimo.geracaoTotalKwh;
              double autoconsumo =
                  ultimo.geracaoTotalKwh - ultimo.energiaInjetadaKwh;
              if (autoconsumo < 0) autoconsumo = 0;
              ultimoMesConsumoReal =
                  autoconsumo + ultimo.energiaConsumidaRedeKwh;
            } else {
              ultimoMesConsumoReal = ultimo.energiaConsumidaRedeKwh;

              if (ultimo.energiaInjetadaKwh > 0) {
                ultimoMesProducaoOuRecebido = ultimo.energiaInjetadaKwh;
              } else {
                final boxUsinas = Hive.box<Usina>('usinas');
                final maes = boxUsinas.values.where(
                  (u) =>
                      u.isGeradora &&
                      !u.isDeletado &&
                      u.beneficiarias.any(
                        (b) => b.idUsinaFilha == widget.usina.id,
                      ),
                );

                for (var mae in maes) {
                  final vinculo = mae.beneficiarias.firstWhere(
                    (b) => b.idUsinaFilha == widget.usina.id,
                  );
                  try {
                    final lancMae = box.values.firstWhere(
                      (l) =>
                          l.usinaId == mae.id &&
                          !l.isDeletado &&
                          l.dataReferencia.year == ultimo.dataReferencia.year &&
                          l.dataReferencia.month == ultimo.dataReferencia.month,
                    );
                    ultimoMesProducaoOuRecebido +=
                        lancMae.energiaInjetadaKwh * (vinculo.percentual / 100);
                  } catch (_) {}
                }
              }
            }
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

              // --- A MÁGICA ACONTECE AQUI: CARD DINÂMICO ---
              if (widget.usina.isGeradora)
                _buildDadosTecnicosCard(
                  widget.usina,
                  metricas.totalGeradoKwh,
                  lancamentos.length,
                )
              else
                _buildPerfilConsumoCard(
                  widget.usina,
                  metricas.mediaConsumo3Meses,
                ),
              // ---------------------------------------------
              const SizedBox(height: 20),

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
                          : 'Total Recebido',
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
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.red.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Retido pela Concessionária (Taxa Mínima)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_numero.format(retidoConcessionaria)} kWh',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                          color: Colors.red.shade900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Volume de energia da rede que você consumiu, mas não pôde usar os seus créditos para abater devido à cobrança obrigatória do Custo de Disponibilidade (ex: 100 kWh/mês).',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.red.shade700,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
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
                ...ultimos6Lancamentos.map((l) => _buildLancamentoCard(l)),

                if (lancamentosOrdenados.length > 6)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: OutlinedButton(
                      onPressed: () => _mostrarHistoricoCompleto(
                        context,
                        lancamentosOrdenados,
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
  ) {
    double autoconsumo = 0;

    double totalCreditoTeorico = 0;
    List<Map<String, dynamic>> listaCreditosTeoricos = [];

    if (widget.usina.isGeradora) {
      autoconsumo = lancamento.geracaoTotalKwh - lancamento.energiaInjetadaKwh;
      if (autoconsumo < 0) autoconsumo = 0;
    }

    if (widget.usina.isBeneficiaria) {
      final boxUsinas = Hive.box<Usina>('usinas');
      final boxLanc = Hive.box<LancamentoMensal>('lancamentos');
      final maes = boxUsinas.values.where(
        (u) =>
            u.isGeradora &&
            !u.isDeletado &&
            u.beneficiarias.any((b) => b.idUsinaFilha == widget.usina.id),
      );

      for (var mae in maes) {
        final vinculo = mae.beneficiarias.firstWhere(
          (b) => b.idUsinaFilha == widget.usina.id,
        );
        try {
          final lancMae = boxLanc.values.firstWhere(
            (l) =>
                l.usinaId == mae.id &&
                !l.isDeletado &&
                l.dataReferencia.year == lancamento.dataReferencia.year &&
                l.dataReferencia.month == lancamento.dataReferencia.month,
          );
          double recebidoTeorico =
              lancMae.energiaInjetadaKwh * (vinculo.percentual / 100);
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

    double consumoTotalReal = 0;
    double saldoFisico = 0;

    double creditoPratico = lancamento.energiaInjetadaKwh;

    if (widget.usina.isGeradora) {
      consumoTotalReal = autoconsumo + lancamento.energiaConsumidaRedeKwh;
      saldoFisico =
          lancamento.energiaInjetadaKwh - lancamento.energiaConsumidaRedeKwh;
    } else {
      consumoTotalReal = lancamento.energiaConsumidaRedeKwh;
      saldoFisico = creditoPratico - lancamento.energiaConsumidaRedeKwh;
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
                          '${_numero.format(lancamento.geracaoTotalKwh)} kWh',
                          boldValue: true,
                        ),
                        _buildDetailRow(
                          'Autoconsumo',
                          '${_numero.format(autoconsumo)} kWh',
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
                            double qtdEnviada =
                                lancamento.energiaInjetadaKwh *
                                (b.percentual / 100);
                            return _buildDetailRow(
                              '--> ${b.nome} (${b.percentual.toStringAsFixed(0)}%)',
                              '${_numero.format(qtdEnviada)} kWh',
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
                                    '${_numero.format(consumoTotalReal)} kWh',
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
                                    '- ${_numero.format(creditoPratico)} kWh',
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

                      if (widget.usina.isBeneficiaria &&
                          listaCreditosTeoricos.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Origem dos Créditos (Cálculo Teórico):',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        ...listaCreditosTeoricos.map(
                          (c) => _buildDetailRow(
                            ' - ${c['nome']}',
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
                        _buildDetailRow(
                          'Crédito Aplicado (Real na Fatura)',
                          '${_numero.format(creditoPratico)} kWh',
                          boldValue: true,
                          colorValue: Colors.green,
                        ),

                        if ((totalCreditoTeorico - creditoPratico).abs() > 0.1)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 8),
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
                                    'Diferença (Perda/Retenção): ${_numero.format(totalCreditoTeorico - creditoPratico)} kWh',
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
                        const Divider(height: 16, indent: 20, endIndent: 20),
                      ],

                      if (widget.usina.isGeradora)
                        _buildDetailRow(
                          'Consumo Total do Local',
                          '${_numero.format(consumoTotalReal)} kWh',
                          boldValue: true,
                        ),
                      _buildDetailRow(
                        widget.usina.isBeneficiaria
                            ? 'Gasto da Concessionária'
                            : 'Da Concessionária (Rede)',
                        '${_numero.format(lancamento.energiaConsumidaRedeKwh)} kWh',
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
                        _moeda.format(lancamento.tarifaKwh),
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
                      _buildSectionHeader(
                        'Balanço Financeiro (Energia)',
                        Icons.balance,
                      ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: saldoFisico >= 0
                              ? Colors.green.shade50
                              : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: saldoFisico >= 0
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
                                  saldoFisico >= 0
                                      ? 'Saldo do Mês (Sobrou)'
                                      : 'Déficit (Faltou)',
                                  style: TextStyle(
                                    color: saldoFisico >= 0
                                        ? Colors.green.shade800
                                        : Colors.red.shade800,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${saldoFisico >= 0 ? "+" : ""}${_numero.format(saldoFisico)} kWh',
                                  style: TextStyle(
                                    color: saldoFisico >= 0
                                        ? Colors.green.shade800
                                        : Colors.red.shade800,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            if (saldoFisico < 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  "Atenção: O consumo superou os créditos recebidos. Esse déficit usará o saldo acumulado anterior ou será cobrado.",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.red.shade800,
                                    fontStyle: FontStyle.italic,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                          ],
                        ),
                      ),
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
                  color: Colors.deepOrange.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                mes,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
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
                      widget.usina.isGeradora ? 'Produziu' : 'Recebeu',
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

  Widget _buildLancamentoCard(LancamentoMensal item) => Card(
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 10),
    color: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: ListTile(
      onTap: () => _mostrarDetalhesLancamento(context, item),
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
        '${_numero.format(widget.usina.isGeradora ? item.geracaoTotalKwh : item.energiaConsumidaRedeKwh)} kWh',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      trailing: Text(
        _moeda.format(item.valorFaturaR),
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.redAccent,
        ),
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
