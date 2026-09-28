// Caminho: lib/widgets/app_drawer.dart
// Descrição: Menu lateral Mobile. Extrai Nome, Empresa e Cargo do Firestore.
// ALTERAÇÃO: Logout agora usa SessionManager (limpa Hive + Providers + sincroniza antes).

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/auth/login_screen.dart';
import '../services/session_manager.dart';
import '../screens/admin/minha_equipe_screen.dart';
import '../screens/admin/historico_atividades_screen.dart';
import '../screens/configuracao_dados_screen.dart';
import '../screens/admin/meu_plano_screen.dart';
import '../screens/configuracoes_screen.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? "Sem e-mail vinculado";
    final bool isLogado = user != null;

    return Drawer(
      child: FutureBuilder<DocumentSnapshot>(
        future: isLogado
            ? FirebaseFirestore.instance.collection('users').doc(user.uid).get()
            : null,
        builder: (context, snapshot) {
          final userData = snapshot.data?.data() as Map<String, dynamic>?;

          final bool isAdmin = userData?['role'] == 'admin';
          final String nomeEmpresa = userData?['nomeEmpresa'] ?? "";
          final String nomeUsuarioFirestore =
              userData?['nome'] ?? "Carregando...";

          final String cargo = isAdmin ? "Administrador" : "Usuário";

          final letraInicial =
              nomeUsuarioFirestore.isNotEmpty &&
                  nomeUsuarioFirestore != "Carregando..."
              ? nomeUsuarioFirestore[0].toUpperCase()
              : "U";

          return ListView(
            padding: EdgeInsets.zero,
            children: [
              // --- 1. CABEÇALHO ---
              UserAccountsDrawerHeader(
                decoration: BoxDecoration(
                  color: isLogado ? Colors.deepOrange : Colors.grey,
                  image: const DecorationImage(
                    image: NetworkImage(
                      "https://www.transparenttextures.com/patterns/cubes.png",
                    ),
                    fit: BoxFit.cover,
                    opacity: 0.1,
                  ),
                ),
                currentAccountPicture: CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Text(
                    letraInicial,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isLogado ? Colors.deepOrange : Colors.grey,
                    ),
                  ),
                ),
                accountName: Text(
                  nomeEmpresa.isNotEmpty
                      ? "$nomeUsuarioFirestore | $nomeEmpresa"
                      : nomeUsuarioFirestore,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                accountEmail: Text("$cargo • $email"),
              ),

              // --- STATUS DA SINCRONIZAÇÃO ---
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isLogado
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isLogado ? Colors.green : Colors.orange,
                    width: 0.5,
                  ),
                ),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    isLogado ? Icons.cloud_done : Icons.cloud_off,
                    color: isLogado ? Colors.green : Colors.orange,
                  ),
                  title: Text(
                    isLogado ? 'Sincronização Ativa' : 'Modo Offline',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isLogado ? Colors.green[800] : Colors.deepOrange,
                    ),
                  ),
                  subtitle: Text(
                    isLogado
                        ? 'Seus dados estão seguros na nuvem.'
                        : 'Faça login para salvar seus dados.',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),

              // --- 2. ÁREA DO ADMINISTRADOR ---
              if (isAdmin) ...[
                ListTile(
                  leading: const Icon(
                    Icons.workspace_premium,
                    color: Colors.amber,
                  ),
                  title: const Text(
                    'Meu Plano e Empresa',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  subtitle: const Text('Identidade, Nível e Compras'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MeuPlanoScreen()),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.history, color: Colors.blueGrey),
                  title: const Text('Logs do Sistema'),
                  subtitle: const Text('Auditoria de ações da equipe'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const HistoricoAtividadesScreen(),
                      ),
                    );
                  },
                ),
                const Divider(),
              ],

              // --- 3. GESTÃO OPERACIONAL ---
              ListTile(
                leading: const Icon(Icons.people_outline),
                title: const Text('Minha Equipe'),
                subtitle: isAdmin
                    ? const Text('Gerenciar membros')
                    : const Text('Visualizar colegas'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MinhaEquipeScreen(),
                    ),
                  );
                },
              ),

              if (isAdmin)
                ListTile(
                  leading: const Icon(Icons.storage_outlined),
                  title: const Text('Backup e Dados'),
                  subtitle: const Text('Importar CSV / Restaurar'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ConfiguracaoDadosScreen(),
                      ),
                    );
                  },
                ),

              const Divider(),

              // --- 4. CONFIGURAÇÕES GERAIS ---
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Configurações do App'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ConfiguracoesScreen(),
                    ),
                  );
                },
              ),

              const Divider(),

              // --- 5. LOGOUT OU LOGIN ---
              if (isLogado)
                ListTile(
                  leading: const Icon(Icons.exit_to_app, color: Colors.red),
                  title: const Text(
                    'Sair da Conta',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () async {
                    // ✅ Logout centralizado: sincroniza + limpa Hive + Providers + Firebase
                    await SessionManager.logout(context);
                    // Não navegamos manualmente: o StreamBuilder do main.dart
                    // detecta o signOut e volta para LoginScreen.
                    if (context.mounted) {
                      Navigator.pop(context); // fecha o drawer
                    }
                  },
                )
              else
                ListTile(
                  leading: const Icon(Icons.login, color: Colors.green),
                  title: const Text(
                    'Entrar / Criar Conta',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                    );
                  },
                ),

              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }
}
