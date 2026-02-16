// Caminho: lib/screens/admin/historico_atividades_screen.dart
// Descrição: Tela de Auditoria com suporte a novos logs de sincronização e tratamento de erro de índice.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/logger_service.dart';

class HistoricoAtividadesScreen extends StatelessWidget {
  const HistoricoAtividadesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final logger = LoggerService();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          "Logs do Sistema",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: logger.getLogs(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            // Tratamento específico para o erro de índice
            if (snapshot.error.toString().contains('FAILED_PRECONDITION')) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text(
                    "O banco de dados está sendo configurado (Índice Firestore). Aguarde alguns minutos.",
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return const Center(child: Text("Erro ao carregar logs."));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final logs = snapshot.data!.docs;

          if (logs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history_toggle_off,
                    size: 64,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Nenhuma atividade registrada ainda.",
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final doc = logs[index];
              final data = doc.data() as Map<String, dynamic>;

              final DateTime? dt = (data['dataHora'] as Timestamp?)?.toDate();
              final String dataFormatada = dt != null
                  ? DateFormat('dd/MM/yy - HH:mm').format(dt)
                  : 'Sincronizando...';

              final String acaoRaw = data['acao'] ?? 'DESCONHECIDO';
              final String usuario = data['usuarioNome'] ?? 'Usuário';
              final String detalhes = data['detalhes'] ?? '';

              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildAcaoBadge(acaoRaw),
                          Text(
                            dataFormatada,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        detalhes,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                      const Divider(height: 24),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 10,
                            backgroundColor: Colors.deepOrange.shade100,
                            child: Text(
                              usuario.isNotEmpty
                                  ? usuario[0].toUpperCase()
                                  : "U",
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.deepOrange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            usuario,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            acaoRaw.contains('SYNC')
                                ? Icons.sync
                                : Icons.smartphone,
                            size: 12,
                            color: Colors.grey,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildAcaoBadge(String acao) {
    Color color;
    String tituloTraduzido;

    switch (acao) {
      case 'CREATE_PLANT':
        color = Colors.green;
        tituloTraduzido = "NOVA USINA";
        break;
      case 'CREATE_ENTRY':
        color = Colors.green;
        tituloTraduzido = "NOVO LANÇAMENTO";
        break;
      case 'DELETE_PLANT':
        color = Colors.red;
        tituloTraduzido = "USINA REMOVIDA";
        break;
      case 'MEMBER_REMOVED':
        color = Colors.red;
        tituloTraduzido = "MEMBRO REMOVIDO";
        break;
      case 'DATABASE_WIPE':
        color = Colors.red;
        tituloTraduzido = "BANCO LIMPO";
        break;
      case 'INVITE_CREATED':
        color = Colors.blue;
        tituloTraduzido = "CONVITE ENVIADO";
        break;
      case 'INVITE_CANCELLED':
        color = Colors.orange;
        tituloTraduzido = "CONVITE CANCELADO";
        break;
      case 'UPDATE_PLANT':
        color = Colors.blue;
        tituloTraduzido = "USINA EDITADA";
        break;
      case 'UPDATE_ENTRY':
        color = Colors.blue;
        tituloTraduzido = "LANÇAMENTO EDITADO";
        break;
      case 'EXPORT_JSON':
      case 'EXPORT_CSV':
        color = Colors.purple;
        tituloTraduzido = "RELATÓRIO GERADO";
        break;
      case 'IMPORT_CSV':
        color = Colors.teal;
        tituloTraduzido = "DADOS IMPORTADOS";
        break;
      case 'SYNC_SUCCESS':
        color = Colors.teal;
        tituloTraduzido = "SINCRONIZAÇÃO OK";
        break;
      case 'SYNC_ERROR':
        color = Colors.red;
        tituloTraduzido = "ERRO NA SYNC";
        break;
      case 'BANCO_LIMPO':
        color = Colors.blueGrey;
        tituloTraduzido = "FAXINA REALIZADA";
        break;
      default:
        color = Colors.grey;
        tituloTraduzido = acao.replaceAll('_', ' ');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        tituloTraduzido,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
