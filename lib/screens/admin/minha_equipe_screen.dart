// Caminho: lib/screens/admin/minha_equipe_screen.dart
// Descrição: Gestão de Equipe com Remoção Segura (Emancipação) e Convites Inteligentes.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/logger_service.dart';
import '../../utils/app_feedback.dart';

class MinhaEquipeScreen extends StatelessWidget {
  const MinhaEquipeScreen({super.key});

  static final _logger = LoggerService();

  // --- 1. LÓGICA DE CONVITE (PARA NOVOS E ANTIGOS) ---
  void _criarConvite(BuildContext context) {
    final emailController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          top: 16,
          left: 24,
          right: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              "Convidar Membro",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration: InputDecoration(
                labelText: "E-mail do novo membro",
                hintText: "usuario@email.com",
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  final email = emailController.text.trim().toLowerCase();

                  // Validação básica de formato de e-mail
                  if (email.isEmpty || !email.contains('@')) {
                    AppFeedback.show(
                      ctx,
                      "Digite um e-mail válido.",
                      isError: true,
                    );
                    return;
                  }

                  Navigator.pop(ctx);

                  try {
                    final currentUser = FirebaseAuth.instance.currentUser;
                    final userDoc = await FirebaseFirestore.instance
                        .collection('users')
                        .doc(currentUser?.uid)
                        .get();

                    final empresaId =
                        userDoc.data()?['empresaId'] ?? currentUser?.uid;
                    final nomeEmpresa =
                        userDoc.data()?['nome'] ?? "Nossa Equipe";

                    // 1. Verifica se já existe convite pendente
                    final conviteExistente = await FirebaseFirestore.instance
                        .collection('invites')
                        .where('email', isEqualTo: email)
                        .where('empresaId', isEqualTo: empresaId)
                        .where('status', isEqualTo: 'pendente')
                        .get();

                    if (conviteExistente.docs.isNotEmpty) {
                      if (context.mounted) {
                        AppFeedback.show(
                          context,
                          "Já existe um convite pendente para este e-mail.",
                          isError: true,
                        );
                      }
                      return;
                    }

                    // 2. Registra o convite no Firestore (O Radar do outro usuário vai ler isso)
                    await FirebaseFirestore.instance.collection('invites').add({
                      'email': email,
                      'enviadoPor': currentUser?.uid,
                      'nomeEmpresa': nomeEmpresa,
                      'empresaId': empresaId,
                      'data': FieldValue.serverTimestamp(),
                      'status': 'pendente',
                    });

                    await _logger.logAction(
                      "INVITE_CREATED",
                      "Enviou convite para: $email",
                    );

                    // 3. Compartilha o link ou mensagem
                    // ignore: deprecated_member_use
                    await Share.share(
                      'Olá! Convido-te para participar da minha equipe no App SolarInsight. Se já tens o app, basta abri-lo para aceitar o convite. Se não, usa este e-mail para o cadastro: $email',
                      subject: 'Convite para Equipe SolarInsight',
                    );
                  } catch (e) {
                    if (context.mounted) {
                      AppFeedback.show(
                        context,
                        "Erro ao processar convite.",
                        isError: true,
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text("CRIAR E ENVIAR CONVITE"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 2. REMOÇÃO DE MEMBRO (EMANCIPAÇÃO SEGURA) ---
  void _confirmarRemocao(BuildContext context, String docId, String nome) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.person_remove_outlined,
              color: Colors.red,
              size: 40,
            ),
            const SizedBox(height: 16),
            Text(
              "Remover $nome?",
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "O usuário perderá o acesso aos seus dados, mas tudo o que ele já cadastrou continuará salvo na sua empresa.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("CANCELAR"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      try {
                        // EMANCIPAÇÃO: O usuário volta a ser "dono de si mesmo"
                        // Ele perde o vínculo com a sua empresaId, mas mantém a conta dele ativa
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(docId)
                            .update({
                              'empresaId': docId, // Volta a ser o próprio UID
                              'role': 'admin', // Volta a ser admin de si mesmo
                            });

                        await _logger.logAction(
                          "MEMBER_REMOVED",
                          "Removeu $nome da equipe (acesso revogado).",
                        );

                        if (context.mounted) {
                          AppFeedback.show(
                            context,
                            "Acesso de $nome revogado.",
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          AppFeedback.show(
                            context,
                            "Erro ao remover membro.",
                            isError: true,
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("REMOVER"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- 3. CANCELAMENTO DE CONVITE ---
  Future<void> _cancelarConvite(String docId, String email) async {
    await _logger.logAction(
      "INVITE_CANCELLED",
      "Cancelou convite para: $email",
    );
    await FirebaseFirestore.instance.collection('invites').doc(docId).delete();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .snapshots(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final userDataLogado =
            userSnapshot.data?.data() as Map<String, dynamic>?;
        final String roleLogado = userDataLogado?['role'] ?? 'user';
        final bool isAdminLogado = roleLogado == 'admin';
        final String empresaIdLogado =
            userDataLogado?['empresaId'] ?? currentUserId ?? '';

        return Scaffold(
          appBar: AppBar(
            title: const Text("Gestão de Equipe"),
            backgroundColor: Colors.white,
            elevation: 0,
            foregroundColor: Colors.black,
          ),
          backgroundColor: const Color(0xFFF5F7FA),
          floatingActionButton: isAdminLogado
              ? FloatingActionButton.extended(
                  heroTag: 'btn_equipe_fab',
                  onPressed: () => _criarConvite(context),
                  label: const Text("Novo Convite"),
                  icon: const Icon(Icons.person_add),
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                )
              : null,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "MEMBROS ATIVOS",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),

                // Lista de Usuários Vinculados à Empresa
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .where('empresaId', isEqualTo: empresaIdLogado)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final users = snapshot.data!.docs;

                    if (users.isEmpty) {
                      return _cardVazio("Nenhum membro ativo.");
                    }

                    return Column(
                      children: users.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final bool isMe = doc.id == currentUserId;
                        final bool isUserAdmin = data['role'] == 'admin';
                        final bool podeExcluir = isAdminLogado && !isMe;

                        return Card(
                          color: Colors.white,
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: isMe
                                  ? Colors.deepOrange.withValues(alpha: 0.2)
                                  : Colors.grey.shade200,
                            ),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isUserAdmin
                                  ? Colors.amber.shade50
                                  : Colors.green.shade50,
                              child: Text(
                                data['nome']?[0].toUpperCase() ?? "?",
                                style: TextStyle(
                                  color: isUserAdmin
                                      ? Colors.amber.shade800
                                      : Colors.green.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              data['nome'] ?? "Sem Nome",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              isUserAdmin
                                  ? "Administrador"
                                  : "Membro da Equipe",
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: podeExcluir
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                    onPressed: () => _confirmarRemocao(
                                      context,
                                      doc.id,
                                      data['nome'],
                                    ),
                                  )
                                : (isMe
                                      ? const Icon(
                                          Icons.star,
                                          color: Colors.amber,
                                          size: 18,
                                        )
                                      : null),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),

                if (isAdminLogado) ...[
                  const SizedBox(height: 32),
                  const Text(
                    "CONVITES ENVIADOS (AGUARDANDO)",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      fontSize: 11,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('invites')
                        .where('status', isEqualTo: 'pendente')
                        .where('empresaId', isEqualTo: empresaIdLogado)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox();
                      final myInvites = snapshot.data!.docs;

                      if (myInvites.isEmpty) {
                        return _cardVazio("Nenhum convite pendente.");
                      }

                      return Column(
                        children: myInvites.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final String inviteEmail = data['email'] ?? "";
                          return Card(
                            color: Colors.white,
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Color(0xFFFFF3E0),
                                child: Icon(
                                  Icons.mail_outline,
                                  color: Colors.orange,
                                ),
                              ),
                              title: Text(
                                inviteEmail,
                                style: const TextStyle(fontSize: 14),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.share,
                                      color: Colors.blue,
                                      size: 20,
                                    ),
                                    // ignore: deprecated_member_use
                                    onPressed: () => Share.share(
                                      "Convite SolarInsight para: $inviteEmail",
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.grey,
                                      size: 20,
                                    ),
                                    onPressed: () =>
                                        _cancelarConvite(doc.id, inviteEmail),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 80),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _cardVazio(String texto) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox, color: Colors.grey.shade300, size: 32),
          const SizedBox(height: 8),
          Text(
            texto,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
