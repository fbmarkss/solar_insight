// Caminho: lib/screens/auditoria_selection_screen.dart
// Descrição: Tela de Seleção de Unidade para Auditoria.
// Correção: Ajuste na navegação para apontar para a tela de detalhes correta (UsinaDetalhesScreen).

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/usina.dart';
import '../models/lancamento.dart';
// Importamos a tela de detalhes, pois é para lá que vamos ao clicar
import 'usina_detalhes_screen.dart';

class AuditoriaSelectionScreen extends StatelessWidget {
  const AuditoriaSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      // SEM APPBAR (Gerenciada pela MainNavigationScreen)
      body: ValueListenableBuilder(
        valueListenable: Hive.box<Usina>('usinas').listenable(),
        builder: (context, Box<Usina> box, _) {
          final usinas = box.values.where((u) => u.ativa).toList();

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // --- CABEÇALHO ---
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Auditoria Energética',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    'Selecione uma unidade para analisar',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // --- CONTEÚDO ---
              if (usinas.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 50),
                    child: Text("Nenhuma usina cadastrada."),
                  ),
                )
              else
                ...usinas.map((usina) => _buildUsinaCard(context, usina)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildUsinaCard(BuildContext context, Usina usina) {
    final boxLancamentos = Hive.box<LancamentoMensal>('lancamentos');
    final lancamentos = boxLancamentos.values
        .where((l) => l.usinaId == usina.id)
        .toList();

    lancamentos.sort((a, b) => b.dataReferencia.compareTo(a.dataReferencia));
    final ultimo = lancamentos.isNotEmpty ? lancamentos.first : null;

    String textoStatus = "Sem dados recentes";
    Color corStatus = Colors.grey;

    if (ultimo != null) {
      if (usina.isGeradora) {
        if (ultimo.geracaoTotalKwh > ultimo.energiaConsumidaRedeKwh) {
          textoStatus = "Superavit (Gerou mais)";
          corStatus = Colors.green;
        } else {
          textoStatus = "Déficit (Consumiu mais)";
          corStatus = Colors.orange;
        }
      } else {
        textoStatus = "Beneficiária de Créditos";
        corStatus = Colors.blue;
      }
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          // --- CORREÇÃO AQUI ---
          // Navegamos para os detalhes da usina, não para a tela de auditoria geral
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => UsinaDetalhesScreen(usina: usina),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: usina.isGeradora
                      ? Colors.orange.withValues(alpha: 0.1)
                      : Colors.blue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  usina.isGeradora ? Icons.wb_sunny : Icons.home_work,
                  color: usina.isGeradora ? Colors.orange : Colors.blue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      usina.nome,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.circle, size: 8, color: corStatus),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            textoStatus,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
