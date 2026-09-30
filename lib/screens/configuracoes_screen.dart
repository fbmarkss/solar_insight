// Caminho: lib/screens/configuracoes_screen.dart
// Descrição: Tela de Ajustes Gerais (Logout, Sync, Perfil e Pausa de Sync).
//
// ALTERAÇÕES DESTA VERSÃO:
//   1. Bloco "Sincronização" agora respeita o plano da EMPRESA:
//      - Switch "Pausar Sincronização": desabilitado se grátis.
//      - Botão "Sincronizar Agora": desabilitado se grátis + clique abre Paywall.
//   2. Botão "Sair" agora usa SessionManager.logout(context):
//      - Limpa Hive + reseta Providers + sync best-effort + signOut.
//      - Sem navegação manual: o StreamBuilder do main.dart reage sozinho.
//   3. Todo o resto permanece intacto.

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../services/sincronizacao_service.dart';
import '../services/subscription_provider.dart';
import '../services/session_manager.dart';
import '../utils/app_feedback.dart';
import 'paywall_screen.dart';

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

    return Consumer<SubscriptionProvider>(
      builder: (context, sub, _) {
        // ✅ Plano da EMPRESA (herdado do dono se for colaborador)
        final bool podeSincronizar = sub.podeSincronizar();

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          appBar: AppBar(
            title: const Text(
              "Configurações",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
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

              // =============================================================
              // 🎯 AVISO "FUNÇÃO PRO" (só aparece se grátis)
              // =============================================================
              if (!podeSincronizar)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock_outline,
                        color: Colors.amber.shade800,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Sincronização é Função PRO",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              "No plano grátis, use Backup/Restore em 'Gestão de Dados' para migrar entre dispositivos.",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

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
                      activeThumbColor: Colors.deepOrange,
                      secondary: Icon(
                        !podeSincronizar
                            ? Icons.lock_outline
                            : (SincronizacaoService.isPaused
                                  ? Icons.cloud_off
                                  : Icons.cloud_sync),
                        color: !podeSincronizar
                            ? Colors.grey
                            : (SincronizacaoService.isPaused
                                  ? Colors.orange
                                  : Colors.green),
                      ),
                      title: Text(
                        "Pausar Sincronização",
                        style: TextStyle(
                          color: podeSincronizar ? Colors.black87 : Colors.grey,
                        ),
                      ),
                      subtitle: Text(
                        !podeSincronizar
                            ? "Função PRO"
                            : (SincronizacaoService.isPaused
                                  ? "Modo Avião forçado: Salvando apenas no dispositivo"
                                  : "Mantém seus dados enviados para a nuvem automaticamente"),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      value: SincronizacaoService.isPaused,
                      onChanged: !podeSincronizar
                          ? null // ✅ Desabilita se grátis
                          : (bool value) {
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
                                SincronizacaoService.inicializarMotorReativo();
                              }
                            },
                    ),
                    const Divider(height: 1),

                    // BOTÃO DE FORÇAR SYNC
                    ListTile(
                      leading: Icon(
                        podeSincronizar ? Icons.sync : Icons.lock_outline,
                        color: !podeSincronizar
                            ? Colors.grey
                            : (SincronizacaoService.isPaused
                                  ? Colors.grey
                                  : Colors.blue),
                      ),
                      title: Text(
                        "Sincronizar Agora",
                        style: TextStyle(
                          color: podeSincronizar
                              ? (SincronizacaoService.isPaused
                                    ? Colors.grey
                                    : Colors.black87)
                              : Colors.grey,
                        ),
                      ),
                      subtitle: Text(
                        !podeSincronizar
                            ? "Função PRO. Faça upgrade para sincronizar."
                            : "Forçar atualização com a nuvem",
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      onTap: !podeSincronizar
                          ? () {
                              // ✅ Abre o Paywall
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const PaywallScreen(
                                    mensagemMotivo:
                                        "Sincronização automática entre dispositivos é uma função PRO.",
                                  ),
                                ),
                              );
                            }
                          : (SincronizacaoService.isPaused
                                ? () {
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
                                      final resultado =
                                          await SincronizacaoService()
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
                                  }),
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
                    // ✅ Logout centralizado: sync best-effort → limpa Hive
                    //    → reseta Providers → reset motor → signOut.
                    // O StreamBuilder do main.dart detecta o signOut e
                    // troca automaticamente para LoginScreen.
                    await SessionManager.logout(context);
                  },
                ),
              ),

              const SizedBox(height: 40),

              // --- RODAPÉ ---
              const Center(
                child: Column(
                  children: [
                    Text(
                      "SolarInsight v1.0.0 Web/Mobile",
                      style: TextStyle(color: Colors.grey),
                    ),
                    SizedBox(height: 4),
                    Text(
                      "by Fabiano Marques",
                      style: TextStyle(
                        color: Colors.blueGrey,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
