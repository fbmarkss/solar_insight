// Caminho: lib/screens/admin/meu_plano_screen.dart
// Descrição: Tela de Gestão de Empresa com Paywall, Restaurar Compras e Cargo Dinâmico.

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
  String _userRole = "admin"; // Para mostrar se é admin ou user

  @override
  void initState() {
    super.initState();
    _carregarDadosEmpresa();
  }

  Future<void> _carregarDadosEmpresa() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (doc.exists && mounted) {
      setState(() {
        _nomeEmpresaController.text = doc.data()?['nomeEmpresa'] ?? "";
        _userRole = doc.data()?['role'] ?? "admin"; // Puxa o cargo do banco
      });
    }
  }

  Future<void> _salvarNomeEmpresa() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

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
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {'nomeEmpresa': _nomeEmpresaController.text.trim()},
      );

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
    AppFeedback.show(context, "Verificando compras anteriores nas lojas...");
    // Aqui no futuro chamaremos: await Purchases.restorePurchases();
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      // Como é simulação, apenas recarregamos o plano do servidor para ver se algo mudou
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
              return _buildStatusCard(subProvider);
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
                const Text(
                  "Como os membros verão a sua equipe:",
                  style: TextStyle(fontSize: 14, color: Colors.blueGrey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nomeEmpresaController,
                  decoration: InputDecoration(
                    labelText: "Nome Fantasia",
                    hintText: "Ex: Solar Engenharia",
                    prefixIcon: const Icon(
                      Icons.business,
                      color: Colors.deepOrange,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
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
                    onPressed: _isSaving ? null : _salvarNomeEmpresa,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
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
                        : const Text(
                            "SALVAR ALTERAÇÕES",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),
          const Center(
            child: Text(
              "Esta identidade será exibida nos convites e no cabeçalho dos seus funcionários.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(SubscriptionProvider subProvider) {
    bool isPro = subProvider.isPro;
    String nomePlano = isPro ? "PRO" : "GRÁTIS";
    Color corPrincipal = isPro ? Colors.green : Colors.deepOrange;
    IconData iconePlano = isPro ? Icons.workspace_premium : Icons.verified_user;

    // Define o texto do cargo
    String cargoTexto = _userRole == 'admin'
        ? "Administrador"
        : "Membro da Equipe";

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

          if (!isPro) ...[
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
                      "O plano Grátis possui limites de usinas cadastradas. Faça o upgrade para remover os limites.",
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
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PaywallScreen(
                        mensagemMotivo:
                            "Desbloqueie todo o poder da sua gestão solar!",
                      ),
                    ),
                  );
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

          const SizedBox(height: 16),
          // Botão Restaurar Compras (Obrigatório Apple/Google)
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
      ),
    );
  }
}
