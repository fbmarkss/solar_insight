// Caminho: lib/utils/app_feedback.dart
// Descrição: Utilitário para feedbacks visuais elegantes (Sucesso, Erro, Info) sem bloquear a tela.

import 'package:flutter/material.dart';

class AppFeedback {
  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    // Remove qualquer mensagem anterior para não empilhar
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        // Design Flutuante (Floating)
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? Colors.red.shade800 : Colors.green.shade800,
        elevation: 4,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
