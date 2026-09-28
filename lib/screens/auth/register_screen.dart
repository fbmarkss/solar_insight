// Caminho: lib/screens/auth/register_screen.dart
// Descrição: Tela de Cadastro com Layout Responsivo para Web/Mobile (Padrão SaaS).
// ALTERAÇÕES DESTA VERSÃO:
//   - Adicionado SessionManager.prepararNovaSessao() no sucesso do cadastro
//     para garantir limpeza de Hive antes de entrar na nova conta.
//   - Adicionado dispose() dos 4 controllers (boa prática).
//   - UI e layout 100% preservados.

import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/session_manager.dart'; // ✅ NOVO
import '../../utils/app_feedback.dart';
import '../../screens/main_navigation_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nomeController = TextEditingController();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  final _confirmaController = TextEditingController();

  final _authService = AuthService();
  bool _isLoading = false;

  // Variáveis para controlar a visibilidade das senhas
  bool _senhaVisivel = false;
  bool _confirmaVisivel = false;

  @override
  void dispose() {
    _nomeController.dispose();
    _emailController.dispose();
    _senhaController.dispose();
    _confirmaController.dispose();
    super.dispose();
  }

  Future<void> _cadastrar() async {
    FocusScope.of(context).unfocus();

    final nome = _nomeController.text.trim();
    final email = _emailController.text.trim();
    final senha = _senhaController.text.trim();
    final confirma = _confirmaController.text.trim();

    if (nome.isEmpty || email.isEmpty || senha.isEmpty) {
      AppFeedback.show(context, "Preencha todos os campos.", isError: true);
      return;
    }

    if (senha != confirma) {
      AppFeedback.show(context, "As senhas não coincidem.", isError: true);
      return;
    }

    if (senha.length < 6) {
      AppFeedback.show(
        context,
        "A senha deve ter no mínimo 6 caracteres.",
        isError: true,
      );
      return;
    }

    try {
      setState(() => _isLoading = true);

      // O papel de 'admin' é definido dentro deste método no AuthService
      String? erro = await _authService.cadastrar(nome, email, senha);

      if (!mounted) return;

      if (erro == null) {
        // FEEDBACK VISÍVEL: Mostra a mensagem e espera o usuário ler
        AppFeedback.show(context, "Conta criada com sucesso! Bem-vindo.");

        // ✅ Limpa qualquer resíduo do usuário anterior ANTES de entrar
        //    na nova sessão. Evita "contaminação" de dados na Web.
        await SessionManager.prepararNovaSessao();

        await Future.delayed(const Duration(seconds: 2));

        if (!mounted) return;

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
          (route) => false,
        );
      } else {
        AppFeedback.show(context, erro, isError: true);
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.show(context, "Erro: $e", isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
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
            padding: const EdgeInsets.all(24),
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
                                "Criar Conta",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                "Preencha os dados abaixo para se registar.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 32),

                              TextFormField(
                                controller: _nomeController,
                                textCapitalization: TextCapitalization.words,
                                decoration: InputDecoration(
                                  labelText: "Nome Completo",
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  prefixIcon: const Icon(Icons.badge_outlined),
                                ),
                              ),
                              const SizedBox(height: 16),

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
                              const SizedBox(height: 16),

                              // CAMPO SENHA COM BOTÃO VISUALIZAR
                              TextFormField(
                                controller: _senhaController,
                                obscureText: !_senhaVisivel,
                                decoration: InputDecoration(
                                  labelText: "Senha",
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _senhaVisivel
                                          ? Icons.visibility
                                          : Icons.visibility_off,
                                      color: Colors.grey,
                                    ),
                                    onPressed: () {
                                      setState(
                                        () => _senhaVisivel = !_senhaVisivel,
                                      );
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // CAMPO CONFIRMAR SENHA COM BOTÃO VISUALIZAR
                              TextFormField(
                                controller: _confirmaController,
                                obscureText: !_confirmaVisivel,
                                decoration: InputDecoration(
                                  labelText: "Confirmar Senha",
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  prefixIcon: const Icon(Icons.lock_reset),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _confirmaVisivel
                                          ? Icons.visibility
                                          : Icons.visibility_off,
                                      color: Colors.grey,
                                    ),
                                    onPressed: () {
                                      setState(
                                        () => _confirmaVisivel =
                                            !_confirmaVisivel,
                                      );
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 32),

                              SizedBox(
                                height: 55, // Altura padronizada
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _cadastrar,
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
                                          "CRIAR CONTA",
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
