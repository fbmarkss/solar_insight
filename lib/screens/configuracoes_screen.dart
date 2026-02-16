// Caminho: lib/screens/configuracoes_screen.dart
// Descrição: Tela de Ajustes Gerais (Logout, Sync e Perfil). Essencial para a versão Web.

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../services/dashboard_provider.dart';
import '../services/auth_service.dart';
import 'auth/login_screen.dart';

class ConfiguracoesScreen extends StatelessWidget {
  const ConfiguracoesScreen({super.key});

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

          // BOTÃO DE SYNC
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: const Icon(Icons.sync, color: Colors.blue),
              title: const Text("Sincronizar Agora"),
              subtitle: const Text("Forçar atualização com a nuvem"),
              onTap: () async {
                final scaffold = ScaffoldMessenger.of(context);
                final provider = Provider.of<DashboardProvider>(
                  context,
                  listen: false,
                );

                scaffold.showSnackBar(
                  const SnackBar(content: Text('Sincronizando...')),
                );

                final msg = await provider.sincronizarDados();

                scaffold.showSnackBar(
                  SnackBar(
                    content: Text(msg),
                    backgroundColor: msg.contains('Erro')
                        ? Colors.red
                        : Colors.green,
                  ),
                );
              },
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
