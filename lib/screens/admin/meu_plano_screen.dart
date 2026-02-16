// Caminho: lib/screens/admin/meu_plano_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../utils/app_feedback.dart';

class MeuPlanoScreen extends StatefulWidget {
  const MeuPlanoScreen({super.key});

  @override
  State<MeuPlanoScreen> createState() => _MeuPlanoScreenState();
}

class _MeuPlanoScreenState extends State<MeuPlanoScreen> {
  final _nomeEmpresaController = TextEditingController();
  bool _isSaving = false;
  String _planoAtual = "FREE"; // Agora será utilizado na UI

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
        _planoAtual = doc.data()?['plano'] ?? "FREE";
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
          // --- CARD DE STATUS (Usando _planoAtual agora) ---
          _buildStatusCard(),

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
                  color: Colors.black.withValues(
                    alpha: 0.03,
                  ), // Corrigido deprecation
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

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.deepOrange.withValues(alpha: 0.1),
        ), // Corrigido deprecation
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.deepOrange.withValues(
                alpha: 0.1,
              ), // Corrigido deprecation
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_user,
              color: Colors.deepOrange,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "PLANO $_planoAtual", // Campo agora utilizado aqui!
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const Text(
                "Administrador",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
