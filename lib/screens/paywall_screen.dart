// Caminho: lib/screens/paywall_screen.dart
// Descrição: Tela de Vitrine (SaaS) oferecendo o upgrade para o Plano PRO.
//
// ALTERAÇÕES DESTA VERSÃO:
//   1. _simularCompraSucesso() agora escreve o plano no doc do DONO da empresa,
//      não no usuário logado. Colaborador NÃO pode comprar (só o dono).
//   2. Após o upgrade, chama SincronizacaoService.sinalizarUpgradeParaPro()
//      para forçar upload dos dados locais antes de baixar a nuvem.
//   3. UI atualizada para refletir a régua: colaboradores, sync e IA são PRO.
//   4. Todo o resto permanece intacto.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/subscription_provider.dart';
import '../services/sincronizacao_service.dart';
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
      // 1. Pega o usuário logado e valida se é o DONO da empresa
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (context.mounted) {
          AppFeedback.show(
            context,
            "Você precisa estar logado.",
            isError: true,
          );
        }
        return;
      }

      final meuDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!meuDoc.exists) {
        if (context.mounted) {
          AppFeedback.show(context, "Perfil não encontrado.", isError: true);
        }
        return;
      }

      final meusDados = meuDoc.data() as Map<String, dynamic>;
      final empresaId = meusDados['empresaId'] ?? user.uid;
      final isDono = empresaId == user.uid;

      // 2. 🚫 BLOQUEIO: só o DONO da empresa pode fazer upgrade
      if (!isDono) {
        if (context.mounted) {
          AppFeedback.show(
            context,
            "Apenas o administrador da empresa pode fazer upgrade. "
            "Solicite ao dono da conta.",
            isError: true,
          );
          Navigator.pop(context);
        }
        return;
      }

      // 3. Simula o processamento da compra
      await Future.delayed(const Duration(seconds: 2));

      // 4. ✅ Escreve o plano no doc do DONO (que é o próprio usuário, já que isDono=true)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(empresaId)
          .update({'plano': 'pro'});

      debugPrint('🎉 [Paywall] Plano PRO gravado no doc do dono: $empresaId');

      // 5. ✅ Sinaliza upgrade para o motor de sincronização:
      //    na próxima sync, ele vai FORÇAR upload dos dados locais
      //    ANTES de baixar a nuvem (evita perda de dados locais).
      await SincronizacaoService.sinalizarUpgradeParaPro();

      // 6. Atualiza o Provider localmente (UI reage imediatamente)
      if (context.mounted) {
        Provider.of<SubscriptionProvider>(
          context,
          listen: false,
        ).atualizarPlanoForcado('pro');
      }

      if (context.mounted) {
        AppFeedback.show(
          context,
          "🎉 Bem-vindo ao Solar Insight PRO! Sincronizando seus dados...",
          isError: false,
        );

        // Dispara uma sync imediata (best-effort)
        // Não bloqueia a UI: o usuário pode fechar o paywall e o motor
        // já está com a flag `migracaoPosUpgradeAtiva` para subir tudo.
        Future.microtask(() async {
          try {
            await SincronizacaoService().sincronizarTudo();
          } catch (e) {
            debugPrint(
              '⚠️ [Paywall] Sync pós-upgrade falhou (será retentado): $e',
            );
          }
        });

        Navigator.pop(context);
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
                  "Desbloqueie sincronização entre dispositivos, colaboradores e automação por IA.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.blueGrey.shade500,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 40),

                // --- LISTA DE VANTAGENS (atualizada) ---
                _buildVantagemItem(
                  "Usinas Ilimitadas",
                  "Cadastre quantas unidades geradoras e beneficiárias precisar.",
                  Icons.all_inclusive,
                ),
                _buildVantagemItem(
                  "Sincronização Automática",
                  "Seus dados seguros na nuvem e disponíveis em qualquer dispositivo.",
                  Icons.cloud_sync,
                ),
                _buildVantagemItem(
                  "Colaboradores",
                  "Convide sua equipe e gerencie tudo em conjunto (só o admin convida).",
                  Icons.group_add,
                ),
                _buildVantagemItem(
                  "Leitura de Faturas com IA",
                  "Envie o PDF e a IA extrai tarifas, ponta, demanda e taxas em segundos.",
                  Icons.document_scanner,
                ),
                _buildVantagemItem(
                  "Relatórios e Gráficos Avançados",
                  "Visualize ROI, balanço energético e economia de todo o histórico.",
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
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    "A assinatura é da EMPRESA. Todos os colaboradores herdam o PRO.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.blueGrey.shade400,
                      fontStyle: FontStyle.italic,
                    ),
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
