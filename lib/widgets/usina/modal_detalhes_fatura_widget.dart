// Caminho: lib/widgets/usina/modal_detalhes_fatura_widget.dart
// Descrição: BottomSheet para exibir o detalhamento da fatura usando o DTO ProcessamentoCiclo.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/usina.dart';
import '../../models/lancamento.dart';
import '../../utils/calculadora_energetica.dart';
import 'alerta_card_widget.dart';

class ModalDetalhesFaturaWidget extends StatelessWidget {
  final Usina usina;
  final LancamentoMensal lancamento;
  final ProcessamentoCiclo ciclo;
  final VoidCallback onEdit;

  // Formatadores
  final NumberFormat _numero = NumberFormat.decimalPattern('pt_BR');
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  ModalDetalhesFaturaWidget({
    super.key,
    required this.usina,
    required this.lancamento,
    required this.ciclo,
    required this.onEdit,
  });

  // Função helper estática para chamar o bottom sheet
  static void mostrar(
    BuildContext context,
    Usina usina,
    LancamentoMensal lancamento,
    ProcessamentoCiclo ciclo,
    VoidCallback onEdit,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ModalDetalhesFaturaWidget(
          usina: usina,
          lancamento: lancamento,
          ciclo: ciclo,
          onEdit: onEdit,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      tooltip: 'Editar Lançamento',
                      onPressed: () {
                        Navigator.pop(context);
                        onEdit(); // Chama a função passada pelo pai
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      tooltip: 'Fechar',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
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
                  // ==========================================
                  // 1. DADOS DE GERAÇÃO (Apenas Geradoras)
                  // ==========================================
                  if (usina.isGeradora) ...[
                    _buildSectionHeader('Produção Local', Icons.solar_power),
                    _buildDetailRow(
                      'Geração Total (Inversor)',
                      '${_numero.format(ciclo.geracaoTotal)} kWh',
                      boldValue: true,
                    ),
                    _buildDetailRow(
                      'Autoconsumo Simultâneo',
                      '${_numero.format(ciclo.autoconsumo)} kWh',
                      colorValue: Colors.purple,
                    ),
                    _buildDetailRow(
                      'Injetado na Rede (Excedente)',
                      '${_numero.format(ciclo.injetadoNaRede)} kWh',
                      colorValue: Colors.blue,
                    ),
                    const Divider(height: 30),
                  ],

                  // ==========================================
                  // 2. RECEBIMENTO E CONSUMO (Todas)
                  // ==========================================
                  _buildSectionHeader('Consumo e Créditos', Icons.receipt_long),
                  _buildDetailRow(
                    'Consumo Registrado (Rede)',
                    '${_numero.format(ciclo.consumoTotal)} kWh',
                    boldValue: true,
                  ),
                  if (ciclo.recebidoDeTerceiros > 0)
                    _buildDetailRow(
                      'Créditos Recebidos (Terceiros)',
                      '${_numero.format(ciclo.recebidoDeTerceiros)} kWh',
                      colorValue: Colors.green.shade700,
                    ),
                  _buildDetailRow(
                    'Custo de Disponibilidade (Retido)',
                    '${_numero.format(ciclo.taxaMinimaRetida)} kWh',
                    colorValue: Colors.red.shade700,
                    isSubtle: true,
                  ),
                  _buildDetailRow(
                    'Tarifa Aplicada',
                    _moeda.format(ciclo.tarifaAplicada),
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
                          'Valor Pago na Fatura:',
                          style: TextStyle(color: Colors.black54),
                        ),
                        Text(
                          _moeda.format(lancamento.valorFaturaR),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 30),

                  // ==========================================
                  // 3. BALANÇO FINANCEIRO / ESTOQUE
                  // ==========================================
                  _buildSectionHeader('Balanço do Mês', Icons.balance),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: ciclo.sobraFisicaDoMes >= 0
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: ciclo.sobraFisicaDoMes >= 0
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
                              ciclo.sobraFisicaDoMes >= 0
                                  ? 'Saldo Gerado (Sobrou)'
                                  : 'Déficit (Faltou)',
                              style: TextStyle(
                                color: ciclo.sobraFisicaDoMes >= 0
                                    ? Colors.green.shade800
                                    : Colors.red.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${ciclo.sobraFisicaDoMes >= 0 ? "+" : ""}${_numero.format(ciclo.sobraFisicaDoMes)} kWh',
                              style: TextStyle(
                                color: ciclo.sobraFisicaDoMes >= 0
                                    ? Colors.green.shade800
                                    : Colors.red.shade800,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Divider(
                          color: ciclo.sobraFisicaDoMes >= 0
                              ? Colors.green.shade200
                              : Colors.red.shade200,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              ciclo.isSaldoEstimado
                                  ? 'Estoque Final (Estimado)'
                                  : 'Estoque Final (Fatura)',
                              style: TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.bold,
                                fontStyle: ciclo.isSaldoEstimado
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                              ),
                            ),
                            Text(
                              '${_numero.format(ciclo.saldoAcumuladoExibicao)} kWh',
                              style: TextStyle(
                                color: ciclo.isSaldoEstimado
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

                  // ==========================================
                  // 4. ALERTAS E AUDITORIA (Dinâmico do Motor)
                  // ==========================================
                  if (ciclo.alertas.isNotEmpty) ...[
                    const SizedBox(height: 30),
                    _buildSectionHeader(
                      'Auditoria e Alertas',
                      Icons.shield_outlined,
                    ),
                    ...ciclo.alertas.map(
                      (alerta) => AlertaCardWidget(alerta: alerta),
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
  }

  // --- Helpers de Construção Visual ---
  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.deepOrange),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value, {
    bool boldValue = false,
    Color? colorValue,
    bool isSubtle = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isSubtle ? Colors.grey.shade600 : Colors.black54,
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: boldValue ? FontWeight.bold : FontWeight.normal,
              color:
                  colorValue ??
                  (isSubtle ? Colors.grey.shade600 : Colors.black87),
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
