// Caminho: lib/screens/importacao_ia_screen.dart
// Descrição: Tela Premium de Importação de Fatura via IA (Recurso PRO) - Integrada com Gemini e Validação de Plano.

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/usina.dart';
import '../services/gemini_service.dart';

class ImportacaoIaScreen extends StatefulWidget {
  final Usina? usinaSelecionada;

  const ImportacaoIaScreen({super.key, this.usinaSelecionada});

  @override
  State<ImportacaoIaScreen> createState() => _ImportacaoIaScreenState();
}

class _ImportacaoIaScreenState extends State<ImportacaoIaScreen> {
  bool _isAnalyzing = false;
  String _statusMessage = 'Aguardando documento...';

  final List<String> _loadingMessages = [
    'Enviando PDF seguro para nuvem...',
    'Identificando concessionária...',
    'Lendo quadro de faturamento...',
    'Separando Tarifas (TE e TUSD)...',
    'Extraindo horosazonalidade (Ponta/Fora Ponta)...',
    'Consolidando dados financeiros...',
    'Quase pronto...',
  ];

  Future<void> _selecionarEAnalisarPdf() async {
    // --- 1. VERIFICAÇÃO DE SEGURANÇA (PAYWALL REAL) ---
    setState(() {
      _isAnalyzing = true;
      _statusMessage = 'Validando credenciais de acesso...';
    });

    bool usuarioPodeUsarIA = false;
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final data = doc.data();

        // Regra de Negócio: Admins ou usuários marcados como PRO no Firestore
        bool isAdmin = data?['role'] == 'admin';
        bool isPro = data?['plano'] == 'pro' || data?['isPro'] == true;

        usuarioPodeUsarIA = isAdmin || isPro;
      } catch (e) {
        debugPrint("Erro ao verificar plano: $e");
      }
    }

    // Se não tiver permissão, aborta e mostra o painel de cobrança!
    if (!usuarioPodeUsarIA) {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          _statusMessage = 'Aguardando documento...';
        });
        _mostrarPaywall();
      }
      return;
    }
    // --------------------------------------------------

    // --- 2. SE FOR PRO/ADMIN, CONTINUA O FLUXO NORMAL ---
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );

    if (result != null) {
      PlatformFile file = result.files.first;

      setState(() {
        _isAnalyzing = true;
        _statusMessage = _loadingMessages[0];
      });

      _iniciarAnimacaoDeStatus();

      final geminiService = GeminiService();
      Map<String, dynamic>? dadosExtraidos;

      if (file.bytes != null) {
        dadosExtraidos = await geminiService.analisarFaturaPdf(file.bytes!);
      }

      if (!mounted) return;

      setState(() {
        _isAnalyzing = false;
      });

      if (dadosExtraidos != null) {
        _mostrarSucesso('Fatura lida com sucesso! Redirecionando...');

        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.pop(context, dadosExtraidos);
          }
        });
      } else {
        _mostrarErro(
          'Não foi possível ler esta fatura. Verifique se o PDF é válido e tente novamente.',
        );
      }
    } else {
      // Caso o usuário cancele a seleção do arquivo
      setState(() {
        _isAnalyzing = false;
        _statusMessage = 'Aguardando documento...';
      });
    }
  }

  void _iniciarAnimacaoDeStatus() async {
    for (int i = 1; i < _loadingMessages.length; i++) {
      if (!_isAnalyzing || !mounted) break;
      await Future.delayed(
        const Duration(seconds: 1),
      ); // Animação sincronizada com a IA
      if (mounted) {
        setState(() {
          _statusMessage = _loadingMessages[i];
        });
      }
    }
  }

  void _mostrarPaywall() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.workspace_premium, color: Colors.amber, size: 28),
            SizedBox(width: 10),
            Text('Recurso PRO'),
          ],
        ),
        content: const Text(
          'A leitura inteligente de faturas com IA extrai Consumo de Ponta, Multas de Reativo e separa a TUSD automaticamente.\n\nFaça o upgrade para o plano PRO para liberar este recurso.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('DEPOIS', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // FUTURO: Navegar para a tela de Assinatura/Planos aqui
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('VER PLANOS'),
          ),
        ],
      ),
    );
  }

  void _mostrarSucesso(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(mensagem)),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _mostrarErro(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(mensagem)),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF6D365), Color(0xFFFDA085)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'AUDITORIA PRO',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Leitura Inteligente',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Envie o PDF da sua conta de energia. Nossa Inteligência Artificial fará a leitura de tarifas, ponta, demanda e taxas complexas em segundos.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.blueGrey,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 40),
              GestureDetector(
                onTap: _isAnalyzing ? null : _selecionarEAnalisarPdf,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: double.infinity,
                  height: 250,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _isAnalyzing
                          ? Colors.blue.shade300
                          : Colors.deepOrange.shade200,
                      width: 2,
                      style: BorderStyle.solid,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _isAnalyzing
                            ? Colors.blue.withValues(alpha: 0.1)
                            : Colors.deepOrange.withValues(alpha: 0.05),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isAnalyzing) ...[
                        const CircularProgressIndicator(color: Colors.blue),
                        const SizedBox(height: 24),
                        Text(
                          _statusMessage,
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Aguarde um instante...',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.deepOrange.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.upload_file,
                            size: 48,
                            color: Colors.deepOrange.shade400,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Toque para enviar o PDF',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Suporta faturas Grupo A e Grupo B',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
