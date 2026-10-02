// Caminho: lib/screens/usina_detalhes_screen.dart
// Descrição: Dashboard de Performance da Usina.
// Versão: V4.0 — ARQUITETURA LIMPA (Baseada em DTO e Componentes).
// - REMOVIDO: Toda a lógica matemática e de auditoria (delegada para CalculadoraEnergetica).
// - ADICIONADO: Integração com PainelPerformanceWidget, ModalDetalhesFaturaWidget e AlertaCardWidget.
// - MANTIDO: Layouts de cabeçalho, perfil e histórico.

import 'package:flutter/foundation.dart';
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

// Importação dos nossos novos componentes visuais
import '../widgets/usina/painel_performance_widget.dart';
import '../widgets/usina/modal_detalhes_fatura_widget.dart';

class UsinaDetalhesScreen extends StatefulWidget {
  final Usina usina;

  const UsinaDetalhesScreen({super.key, required this.usina});

  @override
  State<UsinaDetalhesScreen> createState() => _UsinaDetalhesScreenState();
}

class _UsinaDetalhesScreenState extends State<UsinaDetalhesScreen> {
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final NumberFormat _numero = NumberFormat.decimalPattern('pt_BR');

  // ===========================================================================
  // MÉTODOS DE AÇÃO DA TELA (Calibração e Histórico)
  // ===========================================================================

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

  void _mostrarHistoricoCompleto(
    BuildContext context,
    List<LancamentoMensal> todosLancamentos,
    Map<String, ProcessamentoCiclo> ciclosCache,
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
                    ProcessamentoCiclo ciclo = ciclosCache[lanc.id]!;
                    return _buildLancamentoCard(lanc, ciclo);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // CONSTRUTOR PRINCIPAL DA TELA (BUILD)
  // ===========================================================================

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
          // 1. Coleta e Ordenação dos Dados
          final lancamentos = box.values
              .where((l) => l.usinaId == widget.usina.id && !l.isDeletado)
              .toList();

          final lancamentosOrdenados = List<LancamentoMensal>.from(lancamentos);
          lancamentosOrdenados.sort(
            (a, b) => b.dataReferencia.compareTo(a.dataReferencia),
          );

          // 2. Processamento Centralizado pelo Motor (DTOs)
          Map<String, ProcessamentoCiclo> ciclosCache = {};
          double totalConsumidoDaRede = 0.0;
          double retidoConcessionaria = 0.0;

          for (int i = 0; i < lancamentosOrdenados.length; i++) {
            var atual = lancamentosOrdenados[i];
            var anterior = (i + 1 < lancamentosOrdenados.length)
                ? lancamentosOrdenados[i + 1]
                : null;

            // O Motor gera o "Laudo" completo do mês
            ProcessamentoCiclo ciclo = CalculadoraEnergetica.analisarCiclo(
              widget.usina,
              atual,
              anterior: anterior,
            );
            ciclosCache[atual.id] = ciclo;

            totalConsumidoDaRede += ciclo.consumoTotal;
            retidoConcessionaria += ciclo.taxaMinimaRetida;
          }

          final metricas = CalculadoraEnergetica.calcularMetricasGerais(
            widget.usina,
            lancamentos,
          );

          // 3. Preparação de Dados para o Cabeçalho
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

          final ultimos6Lancamentos = lancamentosOrdenados.take(6).toList();

          // 4. Desenho da Interface
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
            children: [
              // Cabeçalho Principal
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
                  _buildUcHeaderDisplay(),
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

              if (lancamentosOrdenados.isNotEmpty)
                _buildCardPerformanceMensal(
                  DateFormat('MMMM yyyy', 'pt_BR')
                      .format(lancamentosOrdenados.first.dataReferencia)
                      .toUpperCase(),
                  ciclosCache[lancamentosOrdenados.first.id]!,
                  lancamentosOrdenados.first,
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

              // COMPONENTE EXTERNO: Painel de Performance
              PainelPerformanceWidget(
                usina: widget.usina,
                metricas: metricas,
                totalConsumidoDaRede: totalConsumidoDaRede,
              ),

              if (retidoConcessionaria > 0 ||
                  metricas.totalCreditosDesviados > 0) ...[
                _buildPerdasERetencoesCard(
                  retidoConcessionaria,
                  metricas.totalCreditosDesviados,
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
                // Lista de Faturas
                ...ultimos6Lancamentos.map((lanc) {
                  return _buildLancamentoCard(lanc, ciclosCache[lanc.id]!);
                }),

                if (lancamentosOrdenados.length > 6)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: OutlinedButton(
                      onPressed: () => _mostrarHistoricoCompleto(
                        context,
                        lancamentosOrdenados,
                        ciclosCache,
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

  // ===========================================================================
  // WIDGETS INTERNOS DE CABEÇALHO E RESUMO
  // ===========================================================================

  Widget _buildUcHeaderDisplay() {
    bool temNovaUc =
        widget.usina.novaUcConcessionaria != null &&
        widget.usina.novaUcConcessionaria!.trim().isNotEmpty;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          widget.usina.isGeradora ? Icons.wb_sunny : Icons.home_work,
          size: 14,
          color: Colors.grey,
        ),
        const SizedBox(width: 4),
        Text(
          temNovaUc
              ? 'UC: ${widget.usina.novaUcConcessionaria}'
              : 'UC: ${widget.usina.id}',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey,
            fontWeight: temNovaUc ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        if (temNovaUc) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: 'Código anterior UC: ${widget.usina.id}',
            triggerMode: TooltipTriggerMode.tap,
            child: const Icon(Icons.info_outline, size: 14, color: Colors.grey),
          ),
        ],
        const SizedBox(width: 4),
        Text(
          '• ${widget.usina.isGeradora ? "Geradora" : "Beneficiária"}',
          style: const TextStyle(fontSize: 14, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildPerfilConsumoCard(Usina usina, double mediaConsumo) {
    String taxaMinima = "100 kWh (Trifásico)";
    if (usina.tipo.toLowerCase().contains('monof'))
      taxaMinima = "30 kWh (Monofásico)";
    if (usina.tipo.toLowerCase().contains('bif'))
      taxaMinima = "50 kWh (Bifásico)";

    List<Map<String, dynamic>> usinasMaes = [];
    final boxUsinas = Hive.box<Usina>('usinas');

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

    bool isBeneficiariaDeFato = usinasMaes.isNotEmpty || !usina.isGeradora;

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
        ],
      ),
    );
  }

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
    ProcessamentoCiclo ciclo,
    LancamentoMensal ultimoLancamento,
  ) {
    double producaoExibicao = widget.usina.isGeradora
        ? ciclo.geracaoTotal
        : ciclo.totalCreditosDisponiveisNoMes;

    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color.fromARGB(141, 20, 68, 0),
          width: 1.0,
        ),
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
              const Text(
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
                      '${_numero.format(producaoExibicao)} kWh',
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
                      '${_numero.format(ciclo.consumoRealLocal)} kWh',
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
              if (enviadoParaEsta == 0 && b.percentual > 0)
                return const SizedBox.shrink();

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

  Widget _buildPerdasERetencoesCard(double retido, double desviado) {
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
              const Icon(
                Icons.info_outline,
                color: Color.fromARGB(255, 252, 73, 67),
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
                    'Custo de Disponibilidade (virou crédito)',
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
                    'Créditos não compensados (Histórico total)',
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

  // ===========================================================================
  // WIDGET DOS LANÇAMENTOS (Usa o DTO e chama o COMPONENTE EXTERNO Modal)
  // ===========================================================================

  Widget _buildLancamentoCard(LancamentoMensal item, ProcessamentoCiclo ciclo) {
    // A presença de um ícone de alerta agora depende exclusivamente do "Laudo" da calculadora
    bool temAlertaGrave = ciclo.alertas.any(
      (alerta) => alerta['cor'] == 'red' || alerta['cor'] == 'orange',
    );

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.blue.shade100, width: 1.0),
      ),
      child: ListTile(
        onTap: () {
          // CHAMA O COMPONENTE MODAL EXTERNO EM VEZ DA ANTIGA FUNÇÃO GIGANTE
          ModalDetalhesFaturaWidget.mostrar(
            context,
            widget.usina,
            item,
            ciclo,
            () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LancamentoMensalScreen(
                    usinaPreSelecionada: widget.usina,
                    lancamentoParaEditar: item,
                  ),
                ),
              ).then((_) => setState(() {}));
            },
          );
        },
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
            if (temAlertaGrave)
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
  }

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
