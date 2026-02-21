// Caminho: lib/screens/auth/forgot_password_screen.dart
// Descrição: Tela para enviar e-mail de redefinição de senha com Layout Responsivo (Padrão SaaS).

import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../utils/app_feedback.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;

  Future<void> _enviarEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      AppFeedback.show(context, "Digite seu e-mail.", isError: true);
      return;
    }

    setState(() => _isLoading = true);

    String? erro = await _authService.recuperarSenha(email);

    if (mounted) {
      setState(() => _isLoading = false);
      if (erro == null) {
        AppFeedback.show(
          context,
          "E-mail de recuperação enviado! Verifique sua caixa de entrada.",
        );
        Navigator.pop(context); // Volta para o login
      } else {
        AppFeedback.show(context, erro, isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // Fundo cinza padrão do sistema
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              // Limite de largura para Web/Tablet
              constraints: const BoxConstraints(maxWidth: 450),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blueGrey.withValues(alpha: 0.1),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // --- LOGO (Consistência Visual) ---
                              const Icon(
                                Icons.wb_sunny,
                                size: 60,
                                color: Colors.deepOrange,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                "SolarInsight",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.deepOrange,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 32),

                              const Text(
                                "Recuperar Senha",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                "Digite o seu e-mail cadastrado. Enviaremos um link para você criar uma nova senha de acesso.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 32),

                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: InputDecoration(
                                  labelText: "E-mail",
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  prefixIcon: const Icon(Icons.email_outlined),
                                ),
                              ),
                              const SizedBox(height: 32),

                              SizedBox(
                                height: 55, // Altura padronizada
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _enviarEmail,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.deepOrange,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          height: 24,
                                          width: 24,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text(
                                          "ENVIAR E-MAIL",
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.0,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // --- BOTÃO 'X' NO CANTO SUPERIOR DIREITO ---
                        Positioned(
                          top: 16,
                          right: 16,
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.grey),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ==========================================
                  // --- RODAPÉ COM VERSÃO E AUTORIA ---
                  // ==========================================
                  const SizedBox(height: 32),
                  const Column(
                    children: [
                      Text(
                        "SolarInsight v1.0.0 Web/Mobile",
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "by Fabiano Marques",
                        style: TextStyle(
                          color: Colors.blueGrey,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
