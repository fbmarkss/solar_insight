// Caminho: lib/screens/configuracoes_screen.dart
// Descrição: Tela de Ajustes Gerais (Logout, Sync, Perfil e Pausa de Sync). Essencial para a versão Web e Mobile.

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/sincronizacao_service.dart'; // Import atualizado
import '../services/auth_service.dart';
import '../utils/app_feedback.dart'; // Padrão de feedback
import 'auth/login_screen.dart';

class ConfiguracoesScreen extends StatefulWidget {
  const ConfiguracoesScreen({super.key});

  @override
  State<ConfiguracoesScreen> createState() => _ConfiguracoesScreenState();
}

class _ConfiguracoesScreenState extends State<ConfiguracoesScreen> {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? "Usuário";
    final letra = email.isNotEmpty ? email[0].toUpperCase() : "U";

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          "Configurações",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // CABEÇALHO DO USUÁRIO
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.deepOrange.shade50,
                  child: Text(
                    letra,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepOrange,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        email,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        "Conta Ativa",
                        style: TextStyle(color: Colors.green, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          const Text(
            "DADOS E SINCRONIZAÇÃO",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 12),

          // BLOCO DE CONTROLE DE SYNC E PAUSA
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                // INTERRUPTOR DE PAUSA
                SwitchListTile(
                  activeColor: Colors.deepOrange,
                  secondary: Icon(
                    SincronizacaoService.isPaused
                        ? Icons.cloud_off
                        : Icons.cloud_sync,
                    color: SincronizacaoService.isPaused
                        ? Colors.orange
                        : Colors.green,
                  ),
                  title: const Text("Pausar Sincronização"),
                  subtitle: Text(
                    SincronizacaoService.isPaused
                        ? "Modo Avião forçado: Salvando apenas no dispositivo"
                        : "Mantém seus dados enviados para a nuvem automaticamente",
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  value: SincronizacaoService.isPaused,
                  onChanged: (bool value) {
                    setState(() {
                      SincronizacaoService.isPaused = value;
                    });
                    if (value) {
                      AppFeedback.show(
                        context,
                        "Sincronização pausada. Pode trabalhar offline.",
                        isError: true,
                      );
                    } else {
                      AppFeedback.show(
                        context,
                        "Sincronização reativada.",
                        isError: false,
                      );
                      // Desperta o motor invisível para enviar qualquer pendência na fila
                      SincronizacaoService.inicializarMotorReativo();
                    }
                  },
                ),
                const Divider(height: 1),

                // BOTÃO DE FORÇAR SYNC (Fica cinza e inativo se pausado)
                ListTile(
                  leading: Icon(
                    Icons.sync,
                    color: SincronizacaoService.isPaused
                        ? Colors.grey
                        : Colors.blue,
                  ),
                  title: Text(
                    "Sincronizar Agora",
                    style: TextStyle(
                      color: SincronizacaoService.isPaused
                          ? Colors.grey
                          : Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    "Forçar atualização com a nuvem",
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  onTap: SincronizacaoService.isPaused
                      ? () {
                          // Se estiver pausado, avisa porquê de não estar a fazer nada
                          AppFeedback.show(
                            context,
                            "Sincronização está pausada. Desligue a chave acima.",
                            isError: true,
                          );
                        }
                      : () async {
                          AppFeedback.show(
                            context,
                            'Verificando dados...',
                            isError: false,
                          );

                          try {
                            final resultado = await SincronizacaoService()
                                .sincronizarTudo();
                            if (!context.mounted) return;

                            if (resultado.contains('Erro') ||
                                resultado.contains('Sem internet')) {
                              AppFeedback.show(
                                context,
                                resultado,
                                isError: true,
                              );
                            } else if (resultado == 'Sincronizado.') {
                              AppFeedback.show(
                                context,
                                "Tudo já está sincronizado.",
                                isError: false,
                              );
                            } else {
                              AppFeedback.show(
                                context,
                                "Dados sincronizados com sucesso!",
                                isError: false,
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              AppFeedback.show(
                                context,
                                "Erro ao atualizar: $e",
                                isError: true,
                              );
                            }
                          }
                        },
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          const Text(
            "CONTA",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 12),

          // BOTÃO DE LOGOUT
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text("Sair do Aplicativo"),
              subtitle: const Text("Encerrar sessão neste dispositivo"),
              onTap: () async {
                await AuthService().logout();
                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                }
              },
            ),
          ),

          const SizedBox(height: 40),
          const Center(
            child: Text(
              "SolarInsight v1.0.0 Web/Mobile",
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
