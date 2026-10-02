// Caminho: lib/widgets/usina/painel_performance_widget.dart
// Descrição: Componente visual que agrupa os cards de desempenho histórico (Economia, Saldo, ROI e Produção).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/usina.dart';
import '../../utils/calculadora_energetica.dart';

class PainelPerformanceWidget extends StatelessWidget {
  final Usina usina;
  final MetricasGerais metricas;
  final double totalConsumidoDaRede;

  // Formatadores de texto para manter a consistência visual
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final NumberFormat _numero = NumberFormat.decimalPattern('pt_BR');

  PainelPerformanceWidget({
    super.key,
    required this.usina,
    required this.metricas,
    required this.totalConsumidoDaRede,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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

        // Card de Total Economizado (Verde)
        _buildTotalEconomiaCard(metricas.valorTotalEconomizadoR),
        const SizedBox(height: 12),

        // Card de Saldo de Créditos (Azul)
        _buildSaldoCreditosCard(metricas.saldoCreditosEstimado),
        const SizedBox(height: 12),

        // Card de Total Exportado / Recebido (Laranja)
        _buildTotalExportadoCard(),
        const SizedBox(height: 16),

        // Card de ROI (Apenas para Geradoras com Investimento registrado)
        if (usina.totalInvestido > 0 && usina.isGeradora) ...[
          _buildCardROI(
            metricas.percentualRoi,
            usina.totalInvestido,
            metricas.valorTotalEconomizadoR,
          ),
          const SizedBox(height: 16),
        ],

        // Tiras de Métricas (Produção, Autoconsumo, Total Rede) - Apenas Geradoras
        if (usina.isGeradora) ...[
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
      ],
    );
  }

  // ==========================================
  // WIDGETS INTERNOS (Design dos Cards)
  // ==========================================

  Widget _buildTotalEconomiaCard(double valor) {
    return Container(
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
            _moeda.format(valor),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaldoCreditosCard(double valor) {
    return Container(
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
            valor > 0 ? '${_numero.format(valor)} kWh' : 'Sem saldo',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalExportadoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade500, Colors.deepOrange.shade600],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            usina.isGeradora ? 'Total Exportado' : 'Total Recebido (Créditos)',
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
    );
  }

  Widget _buildCardROI(double percentual, double investido, double retorno) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ROI: ${percentual.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: percentual >= 100 ? Colors.green : Colors.black87,
            ),
          ),
          Text(
            'Falta: ${_moeda.format(investido - retorno)}',
            style: const TextStyle(color: Colors.orange),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(
    String label,
    String valor,
    IconData icone,
    Color cor,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: cor, size: 20),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 11,
              height: 1.1,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
