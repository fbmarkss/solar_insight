// Caminho: lib/screens/admin/meu_plano_screen.dart
// Descrição: Tela de Gestão de Empresa com Paywall, Restaurar Compras e Cargo Dinâmico.
//
// ALTERAÇÕES DESTA VERSÃO:
//   1. Remoção da variável '_meuUid' que não estava a ser utilizada (limpeza de código).
//   2. Ajuste do breakpoint de responsividade de 900px para 800px ao abrir o Paywall.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../utils/app_feedback.dart';
import '../../services/subscription_provider.dart';
import '../paywall_screen.dart';

class MeuPlanoScreen extends StatefulWidget {
  const MeuPlanoScreen({super.key});

  @override
  State<MeuPlanoScreen> createState() => _MeuPlanoScreenState();
}

class _MeuPlanoScreenState extends State<MeuPlanoScreen> {
  final _nomeEmpresaController = TextEditingController();
  bool _isSaving = false;
  String _userRole = "admin";
  String _empresaId = "";
  bool _isDono = false; // Removido o _meuUid daqui

  @override
  void initState() {
    super.initState();
    // Removido o _meuUid = FirebaseAuth... daqui
    _carregarDadosEmpresa();
  }

  @override
  void dispose() {
    _nomeEmpresaController.dispose();
    super.dispose();
  }

  Future<void> _carregarDadosEmpresa() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (doc.exists && mounted) {
      final data = doc.data() as Map<String, dynamic>;
      final empresaId = data['empresaId'] ?? user.uid;

      setState(() {
        _nomeEmpresaController.text = data['nomeEmpresa'] ?? "";
        _userRole = data['role'] ?? "admin";
        _empresaId = empresaId;
        _isDono = empresaId == user.uid;
      });
    }
  }

  Future<void> _salvarNomeEmpresa() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Só o dono pode alterar o nome da empresa
    if (!_isDono) {
      AppFeedback.show(
        context,
        "Apenas o administrador pode alterar o nome da empresa.",
        isError: true,
      );
      return;
    }

    if (_nomeEmpresaController.text.trim().isEmpty) {
      AppFeedback.show(
        context,
        "Digite um nome para sua empresa.",
        isError: true,
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      // Grava no doc do dono (que é o próprio usuário, se isDono)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_empresaId)
          .update({'nomeEmpresa': _nomeEmpresaController.text.trim()});

      if (mounted) {
        AppFeedback.show(context, "Identidade da empresa atualizada!");
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.show(context, "Erro ao salvar: $e", isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Simula a restauração de compras exigida pelas lojas
  Future<void> _restaurarCompras() async {
    if (!_isDono) {
      AppFeedback.show(
        context,
        "Apenas o administrador pode restaurar compras.",
        isError: true,
      );
      return;
    }

    AppFeedback.show(context, "Verificando compras anteriores nas lojas...");
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      Provider.of<SubscriptionProvider>(
        context,
        listen: false,
      ).carregarPlanoDoServidor();
      AppFeedback.show(
        context,
        "Restauração concluída. O seu plano está atualizado.",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          "Gestão da Empresa",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // --- CARD DE STATUS INTEGRADO AO PROVIDER ---
          Consumer<SubscriptionProvider>(
            builder: (context, subProvider, child) {
              return _buildStatusCard(subProvider, context);
            },
          ),

          const SizedBox(height: 32),

          // --- SEÇÃO DE IDENTIDADE ---
          const Text(
            "NOME DA EMPRESA / EQUIPE",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 12),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isDono
                      ? "Como os membros verão a sua equipe:"
                      : "Nome da empresa (definido pelo administrador):",
                  style: const TextStyle(fontSize: 14, color: Colors.blueGrey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nomeEmpresaController,
                  enabled: _isDono, // Só o dono edita
                  decoration: InputDecoration(
                    labelText: "Nome Fantasia",
                    hintText: "Ex: Solar Engenharia",
                    prefixIcon: const Icon(
                      Icons.business,
                      color: Colors.deepOrange,
                    ),
                    filled: true,
                    fillColor: _isDono
                        ? Colors.grey.shade50
                        : Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: (_isSaving || !_isDono)
                        ? null
                        : _salvarNomeEmpresa,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isDono
                          ? Colors.deepOrange
                          : Colors.grey.shade300,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            _isDono
                                ? "SALVAR ALTERAÇÕES"
                                : "SOMENTE ADMIN PODE ALTERAR",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),
          Center(
            child: Text(
              _isDono
                  ? "Esta identidade será exibida nos convites e no cabeçalho dos seus funcionários."
                  : "A identidade da empresa é gerenciada pelo administrador da conta.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // CARD DE STATUS
  // ===========================================================================
  Widget _buildStatusCard(
    SubscriptionProvider subProvider,
    BuildContext context,
  ) {
    final bool isPro = subProvider.isProEmpresa;
    final String nomePlano = isPro ? "PRO" : "GRÁTIS";
    final Color corPrincipal = isPro ? Colors.green : Colors.deepOrange;
    final IconData iconePlano = isPro
        ? Icons.workspace_premium
        : Icons.verified_user;

    // Texto do cargo
    final String cargoTexto = _userRole == 'admin'
        ? "Administrador"
        : "Membro da Equipe";

    // Texto de "quem gerencia"
    final String gerenciadoPor = _isDono
        ? "Você é o titular desta assinatura."
        : "A assinatura é gerenciada pelo administrador da empresa.";

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: corPrincipal.withValues(alpha: isPro ? 0.3 : 0.1),
          width: isPro ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: corPrincipal.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: corPrincipal.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(iconePlano, color: corPrincipal, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "PLANO $nomePlano",
                      style: TextStyle(
                        color: corPrincipal,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      cargoTexto,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Nota sobre quem gerencia
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blueGrey.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  _isDono ? Icons.verified_user : Icons.info_outline,
                  size: 16,
                  color: Colors.blueGrey.shade600,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    gerenciadoPor,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blueGrey.shade700,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // =================================================================
          // GRÁTIS + DONO → Mostra aviso + botão de upgrade + restaurar
          // =================================================================
          if (!isPro && _isDono) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.deepOrange, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "O plano Grátis possui limites de usinas. Faça o upgrade para liberar sincronização, colaboradores e IA.",
                      style: TextStyle(fontSize: 12, color: Colors.brown),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () {
                  // ✅ Alteração do Breakpoint: 900 -> 800
                  bool isDesktop = MediaQuery.of(context).size.width >= 800;

                  if (isDesktop) {
                    showDialog(
                      context: context,
                      builder: (context) => Dialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const ClipRRect(
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                          child: SizedBox(
                            width: 500,
                            height: 650,
                            child: PaywallScreen(
                              mensagemMotivo:
                                  "Desbloqueie todo o poder da sua gestão solar!",
                            ),
                          ),
                        ),
                      ),
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PaywallScreen(
                          mensagemMotivo:
                              "Desbloqueie todo o poder da sua gestão solar!",
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.rocket_launch),
                label: const Text(
                  "FAZER UPGRADE PARA PRO",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],

          // =================================================================
          // GRÁTIS + COLABORADOR → Aviso para contatar admin
          // =================================================================
          if (!isPro && !_isDono) ...[
            const SizedBox(height: 24),
            Container(
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
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Sua empresa está no plano Grátis. Peça ao administrador para fazer o upgrade e liberar todos os recursos.",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // =================================================================
          // PRO + DONO → Mostra restaurar compras
          // =================================================================
          if (isPro && _isDono) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: _restaurarCompras,
                icon: const Icon(Icons.restore, size: 18),
                label: const Text("Restaurar Compras Anteriores"),
                style: TextButton.styleFrom(foregroundColor: Colors.blueGrey),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
