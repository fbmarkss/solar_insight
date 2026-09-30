// Caminho: lib/screens/importacao_ia_screen.dart
// Descrição: Tela Premium de Importação de Fatura via IA (Recurso PRO).
//
// ALTERAÇÕES DESTA VERSÃO:
//   1. Fonte de verdade do plano trocada:
//      ANTES: lia users/{uid}.plano diretamente do Firestore (bug: colaborador
//             de empresa PRO via 'gratis' e era bloqueado).
//      DEPOIS: usa SubscriptionProvider.isProEmpresa, que herda dinamicamente
//              o plano do DONO da empresa.
//   2. initState() agora chama _verificarPlanoUsuario() após o primeiro frame
//      para garantir que o Provider já esteja disponível.
//   3. Todo o resto permanece intacto (UI, upload, painel de análise).

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../models/usina.dart';
import '../services/gemini_service.dart';
import '../services/subscription_provider.dart';
import 'paywall_screen.dart';

class ImportacaoIaScreen extends StatefulWidget {
  final Usina? usinaSelecionada;

  const ImportacaoIaScreen({super.key, this.usinaSelecionada});

  @override
  State<ImportacaoIaScreen> createState() => _ImportacaoIaScreenState();
}

class _ImportacaoIaScreenState extends State<ImportacaoIaScreen> {
  bool _isAnalyzing = false;
  String _statusMessage = 'Aguardando documento...';

  // Variável que controla a tela: null = carregando, true = PRO, false = Bloqueado
  bool? _isUsuarioPro;

  // --- VARIÁVEIS PARA O PAINEL DE ANÁLISE (DEBUG) ---
  bool _mostrarDebug = false;
  Map<String, dynamic>? _dadosProcessados;

  final List<String> _loadingMessages = [
    'Enviando PDF seguro para nuvem...',
    'Identificando concessionária...',
    'Lendo quadro de faturamento...',
    'Separando Tarifas (TE e TUSD)...',
    'Extraindo horosazonalidade (Ponta/Fora Ponta)...',
    'Consolidando dados financeiros...',
    'Quase pronto...',
  ];

  @override
  void initState() {
    super.initState();
    // ✅ Usa postFrameCallback para garantir que o Provider já esteja montado
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verificarPlanoUsuario();
    });
  }

  /// ✅ VERIFICA O PLANO VIA PROVIDER (herda do dono da empresa).
  /// Antes lia direto do Firestore, o que bloqueava colaboradores de
  /// empresas PRO. Agora usa a fonte única de verdade.
  Future<void> _verificarPlanoUsuario() async {
    if (!mounted) return;

    final sub = Provider.of<SubscriptionProvider>(context, listen: false);

    // Aguarda o SubscriptionProvider terminar de carregar o plano
    // (evita falso-negativo quando a tela abre antes do provider resolver)
    int tentativas = 0;
    while (sub.isLoading && tentativas < 30) {
      await Future.delayed(const Duration(milliseconds: 100));
      tentativas++;
      if (!mounted) return;
    }

    if (mounted) {
      setState(() {
        _isUsuarioPro = sub.isProEmpresa;
      });
      debugPrint(
        '🧠 [ImportacaoIA] Plano verificado: isProEmpresa = ${sub.isProEmpresa}',
      );
    }
  }

  Future<void> _selecionarEAnalisarPdf() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );

    if (result != null) {
      PlatformFile file = result.files.first;

      setState(() {
        _isAnalyzing = true;
        _mostrarDebug = false;
        _statusMessage = _loadingMessages[0];
      });

      _iniciarAnimacaoDeStatus();

      final geminiService = GeminiService();

      try {
        if (file.bytes != null) {
          final dadosExtraidos = await geminiService.analisarFaturaPdf(
            file.bytes!,
          );

          if (!mounted) return;

          if (dadosExtraidos != null) {
            _mostrarSucesso('Fatura lida com sucesso!');

            setState(() {
              _dadosProcessados = dadosExtraidos;
              _mostrarDebug = true;
            });
          }
        }
      } catch (e) {
        if (mounted) {
          _mostrarErro(e.toString().replaceAll('Exception: ', ''));
        }
      } finally {
        if (mounted) {
          setState(() {
            _isAnalyzing = false;
          });
        }
      }
    } else {
      setState(() {
        _isAnalyzing = false;
        _statusMessage = 'Aguardando documento...';
      });
    }
  }

  void _iniciarAnimacaoDeStatus() async {
    for (int i = 1; i < _loadingMessages.length; i++) {
      if (!_isAnalyzing || !mounted) break;
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        setState(() {
          _statusMessage = _loadingMessages[i];
        });
      }
    }
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

              // --- ÁREA DINÂMICA (CARREGANDO / BLOQUEADA / REVISÃO / UPLOAD) ---
              _buildDynamicArea(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDynamicArea() {
    if (_isUsuarioPro == null) {
      // Estado 1: Carregando plano
      return const SizedBox(
        height: 250,
        child: Center(
          child: CircularProgressIndicator(color: Colors.deepOrange),
        ),
      );
    } else if (_isUsuarioPro == false) {
      // Estado 2: Bloqueado (Paywall Embutido)
      return Container(
        width: double.infinity,
        height: 280,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.amber.shade200, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.amber.withValues(alpha: 0.1),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 48, color: Colors.amber.shade600),
            const SizedBox(height: 16),
            const Text(
              'Recurso Exclusivo',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Faça o upgrade para o plano PRO para liberar o preenchimento automático.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PaywallScreen(
                        mensagemMotivo:
                            "Para usar a IA e automatizar os seus lançamentos, assine o plano PRO.",
                      ),
                    ),
                  ).then((_) {
                    // ✅ Após voltar do Paywall, revalida (pode ter virado PRO)
                    _verificarPlanoUsuario();
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'VER PLANOS',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // Estado 3: Liberado (PRO)

      // Se a IA já processou, mostra o Painel de Revisão Clean
      if (_mostrarDebug && _dadosProcessados != null) {
        return _buildPainelAnaliseConcluida();
      }

      // Senão, mostra o botão tradicional de Upload Animado
      return GestureDetector(
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
      );
    }
  }

  // --- PAINEL DE ANÁLISE CLEAN (inalterado) ---
  Widget _buildPainelAnaliseConcluida() {
    String debugText =
        _dadosProcessados!['debugLog'] ??
        'Log de raciocínio não encontrado ou vazio.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.blue.shade100, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withValues(alpha: 0.05),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.psychology,
                      color: Colors.blue.shade700,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Análise Concluída',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          'Veja como a IA interpretou os dados',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(height: 1),
              ),
              Container(
                height: 220,
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    child: Text(
                      debugText,
                      style: TextStyle(
                        color: Colors.blueGrey.shade800,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 55,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context, _dadosProcessados);
            },
            icon: const Icon(Icons.check_circle_outline),
            label: const Text(
              'PREENCHER FORMULÁRIO',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                letterSpacing: 1.0,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () {
              setState(() {
                _mostrarDebug = false;
                _dadosProcessados = null;
                _statusMessage = 'Aguardando documento...';
              });
            },
            child: const Text(
              'Importar arquivo diferente',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}
