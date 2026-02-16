// Caminho: lib/screens/auditoria_individual_screen.dart
// Descrição: Tela de Auditoria Anual com layout de fluxo de abatimento (Consumo vs Créditos).

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../models/usina.dart';
import '../models/lancamento.dart';
import '../utils/calculadora_energetica.dart';

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
      ),
      body: ValueListenableBuilder(
        valueListenable: Hive.box<LancamentoMensal>('lancamentos').listenable(),
        builder: (context, Box<LancamentoMensal> box, _) {
          final lancamentos = box.values
              .where((l) => l.usinaId == usina.id)
              .toList();

          lancamentos.sort(
            (a, b) => b.dataReferencia.compareTo(a.dataReferencia),
          );

          if (lancamentos.isEmpty) return _buildEmptyState();

          final dataFim = lancamentos.first.dataReferencia;
          final dataInicio = lancamentos.last.dataReferencia;
          final String intervaloFormatado =
              "${DateFormat('MMM yyyy', 'pt_BR').format(dataInicio)}  ➔  ${DateFormat('MMM yyyy', 'pt_BR').format(dataFim)}";

          final metricas = CalculadoraEnergetica.calcularMetricasGerais(
            usina,
            lancamentos,
          );

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
              _buildFluxoCreditosSection(),
              const SizedBox(height: 24),
              const Text(
                "Detalhamento Mensal (Fluxo de Abatimento)",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                ),
              ),
              const SizedBox(height: 10),
              ...lancamentos.map((l) => _buildMesAuditoriaCard(l, usina)),
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

  Widget _buildFluxoCreditosSection() {
    final boxUsinas = Hive.box<Usina>('usinas');
    final boxLancamentos = Hive.box<LancamentoMensal>('lancamentos');
    final numero = NumberFormat.decimalPattern('pt_BR');
    List<Widget> tiles = [];

    if (usina.isGeradora) {
      for (var b in usina.beneficiarias) {
        double total = 0;
        final meusLancs = boxLancamentos.values.where(
          (l) => l.usinaId == usina.id,
        );
        for (var l in meusLancs) {
          total += (l.energiaInjetadaKwh * (b.percentual / 100));
        }
        tiles.add(
          _buildFluxoTile(b.nome, b.percentual, total, Colors.orange, numero),
        );
      }
    } else {
      final maes = boxUsinas.values.where(
        (u) =>
            u.isGeradora &&
            u.beneficiarias.any((b) => b.idUsinaFilha == usina.id),
      );
      for (var mae in maes) {
        final vinculo = mae.beneficiarias.firstWhere(
          (b) => b.idUsinaFilha == usina.id,
        );
        double total = 0;
        final lancsMae = boxLancamentos.values.where(
          (l) => l.usinaId == mae.id,
        );
        for (var l in lancsMae) {
          total += (l.energiaInjetadaKwh * (vinculo.percentual / 100));
        }
        tiles.add(
          _buildFluxoTile(
            mae.nome,
            vinculo.percentual,
            total,
            Colors.blue,
            numero,
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
              ? "Destino dos Créditos (Anual)"
              : "Origem dos Créditos (Anual)",
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
    double perc,
    double valor,
    Color cor,
    NumberFormat numero,
  ) {
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
          Text(
            "$nome (${perc.toStringAsFixed(0)}%)",
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
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
    final boxUsinas = Hive.box<Usina>('usinas');
    final boxLancamentos = Hive.box<LancamentoMensal>('lancamentos');

    // Cálculo do crédito do mês
    double creditoNoMes = 0;
    if (!usina.isGeradora) {
      final maes = boxUsinas.values.where(
        (u) =>
            u.isGeradora &&
            u.beneficiarias.any((b) => b.idUsinaFilha == usina.id),
      );
      for (var mae in maes) {
        final v = mae.beneficiarias.firstWhere(
          (b) => b.idUsinaFilha == usina.id,
        );
        try {
          final lm = boxLancamentos.values.firstWhere(
            (x) =>
                x.usinaId == mae.id &&
                x.dataReferencia.year == l.dataReferencia.year &&
                x.dataReferencia.month == l.dataReferencia.month,
          );
          creditoNoMes += (lm.energiaInjetadaKwh * (v.percentual / 100));
        } catch (_) {}
      }
    }

    double consumoReal = usina.isGeradora
        ? ((l.geracaoTotalKwh - l.energiaInjetadaKwh).clamp(
                0,
                double.infinity,
              ) +
              l.energiaConsumidaRedeKwh)
        : l.energiaConsumidaRedeKwh;

    // Lógica de "Abatimento" para o texto
    double saldoAposCredito = usina.isGeradora
        ? (l.energiaInjetadaKwh - l.energiaConsumidaRedeKwh)
        : (creditoNoMes - l.energiaConsumidaRedeKwh);

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
            // Linha 1: O que entrou e o que saiu
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMiniStat(
                  usina.isGeradora ? "Geração Total" : "Consumo Total",
                  "${numero.format(usina.isGeradora ? l.geracaoTotalKwh : consumoReal)} kWh",
                ),
                const Icon(Icons.remove, size: 14, color: Colors.grey),
                _buildMiniStat(
                  usina.isGeradora ? "Consumo Local" : "Crédito Usado",
                  "${numero.format(usina.isGeradora ? consumoReal : (creditoNoMes > consumoReal ? consumoReal : creditoNoMes))} kWh",
                ),
                const Icon(Icons.drag_handle, size: 14, color: Colors.grey),
                _buildMiniStat(
                  usina.isGeradora ? "Injetado" : "Sobrou/Faltou",
                  "${numero.format(usina.isGeradora ? l.energiaInjetadaKwh : saldoAposCredito)} kWh",
                  color: saldoAposCredito >= 0 ? Colors.green : Colors.red,
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
                      "Total de Créditos Recebidos no mês:",
                      style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                    ),
                    Text(
                      "${numero.format(creditoNoMes)} kWh",
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
}
