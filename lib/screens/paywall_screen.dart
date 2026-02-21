// Caminho: lib/screens/paywall_screen.dart
// Descrição: Tela de Vitrine (SaaS) oferecendo o upgrade para o Plano PRO.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/subscription_provider.dart';
import '../utils/app_feedback.dart';

class PaywallScreen extends StatefulWidget {
  final String mensagemMotivo;

  const PaywallScreen({
    super.key,
    this.mensagemMotivo = "Você atingiu o limite do plano Grátis!",
  });

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _isProcessing = false;

  // --- FUNÇÃO SIMULADA DE COMPRA (Até colocarmos o RevenueCat) ---
  Future<void> _simularCompraSucesso(BuildContext context) async {
    setState(() => _isProcessing = true);

    try {
      // Finge que está falando com a Apple/Google...
      await Future.delayed(const Duration(seconds: 2));

      // Pega o utilizador logado
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Vai lá no Firebase e muda a etiqueta de 'gratis' para 'pro'
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'plano': 'pro'});

        // Avisa o nosso Guardião local para ele destrancar as portas IMEDIATAMENTE
        if (context.mounted) {
          Provider.of<SubscriptionProvider>(
            context,
            listen: false,
          ).atualizarPlanoForcado('pro');
        }
      }

      if (context.mounted) {
        AppFeedback.show(
          context,
          "🎉 Bem-vindo ao Solar Insight PRO! Todas as funções foram liberadas.",
          isError: false,
        );
        Navigator.pop(context); // Fecha a tela de vendas
      }
    } catch (e) {
      if (context.mounted) {
        AppFeedback.show(context, "Erro na simulação: $e", isError: true);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Detecta se está num ecrã largo (Web/Tablet) para não deixar a tela gigante
    bool isWeb = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: isWeb ? 500 : double.infinity,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- CABEÇALHO ---
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.rocket_launch_rounded,
                    size: 64,
                    color: Colors.deepOrange,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  widget.mensagemMotivo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.deepOrange,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Eleve sua gestão com o\nSolar Insight PRO",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isWeb ? 32 : 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.blueGrey.shade900,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "Livre-se de planilhas e limites. Tenha controle absoluto sobre a energia gerada e distribuída.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.blueGrey.shade500,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 40),

                // --- LISTA DE VANTAGENS ---
                _buildVantagemItem(
                  "Usinas Ilimitadas",
                  "Cadastre quantas unidades geradoras e beneficiárias precisar.",
                  Icons.all_inclusive,
                ),
                _buildVantagemItem(
                  "Leitura de Faturas com IA",
                  "Chega de digitar. O sistema extrai os dados do PDF automaticamente (Em breve).",
                  Icons.document_scanner,
                ),
                _buildVantagemItem(
                  "Relatórios e Gráficos Avançados",
                  "Visualize o ROI, o balanço energético e a economia de todo o histórico.",
                  Icons.bar_chart,
                ),
                const SizedBox(height: 40),

                // --- BOTÕES DE COMPRA ---
                _isProcessing
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Colors.deepOrange,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ElevatedButton(
                            onPressed: () => _simularCompraSucesso(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepOrange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 4,
                              shadowColor: Colors.deepOrange.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            child: const Column(
                              children: [
                                Text(
                                  "ASSINAR MENSAL - R\$ 29,90",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  "(Simulação de Compra)",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: () => _simularCompraSucesso(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              side: BorderSide(color: Colors.grey.shade300),
                            ),
                            child: const Column(
                              children: [
                                Text(
                                  "PLANO ANUAL (20% OFF)",
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  "R\$ 289,90 / ano",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    "Cancele quando quiser através da sua loja de aplicativos.",
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVantagemItem(String titulo, String descricao, IconData icone) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icone, color: Colors.green.shade700, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  descricao,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.blueGrey.shade500,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
