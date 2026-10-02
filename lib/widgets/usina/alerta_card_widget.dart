// Caminho: lib/widgets/usina/alerta_card_widget.dart
// Descrição: Componente visual padronizado para exibir alertas gerados pela Calculadora.

import 'package:flutter/material.dart';

class AlertaCardWidget extends StatelessWidget {
  final Map<String, dynamic> alerta;

  const AlertaCardWidget({super.key, required this.alerta});

  // Função auxiliar para traduzir o nome da cor em uma cor real do Flutter
  Color _getCorBase(String corNome) {
    switch (corNome) {
      case 'red':
        return Colors.red;
      case 'orange':
        return Colors.orange;
      case 'green':
        return Colors.green;
      case 'blue':
        return Colors.blue;
      default:
        return Colors.blueGrey;
    }
  }

  // Função auxiliar para mapear o nome em String para o ícone correspondente
  IconData _getIcone(String iconeNome) {
    switch (iconeNome) {
      case 'bolt':
        return Icons.bolt;
      case 'domain':
        return Icons.domain;
      case 'hourglass_bottom':
        return Icons.hourglass_bottom;
      case 'monetization_on':
        return Icons.monetization_on;
      case 'gavel':
        return Icons.gavel;
      case 'compare_arrows':
        return Icons.compare_arrows;
      case 'lightbulb_circle':
        return Icons.lightbulb_circle;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Extraímos as propriedades do alerta recebido
    final corBase = _getCorBase(alerta['cor'] ?? 'grey');
    final icone = _getIcone(alerta['icone'] ?? 'warning');
    final titulo = alerta['titulo'] ?? 'Aviso';
    final mensagem = alerta['mensagem'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: corBase.withValues(alpha: 0.05), // Fundo bem claro
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: corBase.withValues(alpha: 0.3),
        ), // Borda suave
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, color: corBase, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(
                    color: corBase,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            mensagem,
            style: TextStyle(
              color: Colors.blueGrey.shade800,
              fontSize: 12,
              height: 1.4, // Melhora a legibilidade do texto
            ),
          ),
        ],
      ),
    );
  }
}
