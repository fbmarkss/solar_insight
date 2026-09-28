// Caminho: lib/screens/auth/login_screen.dart
// Descrição: Tela de Login REAL (Conectada ao Firebase) com Layout Responsivo para Web/Mobile.
// ALTERAÇÕES DESTA VERSÃO:
//   - Removido initState com navegação automática (o StreamBuilder do main.dart é a única fonte de verdade).
//   - Removido import órfão de main_navigation_screen.dart.
//   - Adicionado SessionManager.prepararNovaSessao() no sucesso do login
//     para garantir limpeza de Hive antes de trocar de usuário.
//   - Adicionado dispose() dos controllers (boa prática).
//   - UI e layout 100% preservados.

import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/session_manager.dart'; // ✅ NOVO
import '../../utils/app_feedback.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;

  // ⚠️ initState REMOVIDO INTENCIONALMENTE.
  // O StreamBuilder em main.dart já escuta authStateChanges() e decide
  // automaticamente entre LoginScreen e MainNavigationScreen.
  // Antes havia uma navegação manual aqui que conflitava com o StreamBuilder,
  // causando deslogamento no cold start do Android.

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  Future<void> _fazerLogin() async {
    final email = _emailController.text.trim();
    final senha = _senhaController.text.trim();

    if (email.isEmpty || senha.isEmpty) {
      AppFeedback.show(context, "Informe e-mail e senha.", isError: true);
      return;
    }

    setState(() => _isLoading = true);

    String? erro = await _authService.login(email, senha);

    if (!mounted) return;

    if (erro == null) {
      // ✅ Limpa qualquer resíduo do usuário anterior ANTES de o StreamBuilder
      //    trocar automaticamente para MainNavigationScreen.
      //    Isso evita "contaminação" de dados entre contas na Web.
      await SessionManager.prepararNovaSessao();

      // Não navegamos manualmente: o authStateChanges() do StreamBuilder em
      // main.dart detecta o novo usuário logado e troca a tela.
      // Se o widget já foi desmontado durante o await, apenas ignoramos.
      if (!mounted) return;
      setState(() => _isLoading = false);
    } else {
      setState(() => _isLoading = false);
      AppFeedback.show(context, erro, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Fundo cinza claro clássico do app
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              // Na Web/Tablet limita a 450px. No Mobile ajusta-se à tela.
              constraints: const BoxConstraints(maxWidth: 450),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(40.0),
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // --- LOGO ---
                        const Icon(
                          Icons.wb_sunny,
                          size: 80,
                          color: Colors.deepOrange,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          "SolarInsight",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Colors.deepOrange,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const Text(
                          "Gestão Inteligente de Energia",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                        const SizedBox(height: 40),

                        const Text(
                          "Bem-vindo!",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),

                        // --- INPUTS ---
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: "E-mail",
                            prefixIcon: const Icon(Icons.email_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _senhaController,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _fazerLogin(),
                          decoration: InputDecoration(
                            labelText: "Senha",
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                          ),
                        ),

                        // --- ESQUECI SENHA ---
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ForgotPasswordScreen(),
                                ),
                              );
                            },
                            child: const Text(
                              "Esqueci minha senha",
                              style: TextStyle(
                                color: Colors.deepOrange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // --- BOTÃO ENTRAR ---
                        SizedBox(
                          height: 55,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _fazerLogin,
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
                                    "ENTRAR",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // --- CADASTRO ---
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              "Não tem uma conta?",
                              style: TextStyle(color: Colors.black54),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const RegisterScreen(),
                                  ),
                                );
                              },
                              child: const Text(
                                "Cadastre-se",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepOrange,
                                ),
                              ),
                            ),
                          ],
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
                  // ==========================================
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
