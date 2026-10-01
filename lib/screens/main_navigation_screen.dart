// Caminho: lib/screens/main_navigation_screen.dart
// Descrição: Controlador mestre (Single Page Application na Web, Navegação Híbrida).
//
// ALTERAÇÕES DESTA VERSÃO:
//   1. REMOÇÃO DEFINITIVA dos `ValueListenableBuilder` e `ValueKey` do método build.
//      Isto impede que a sincronização em segundo plano destrua a tela do utilizador
//      (como fechar a Importação da IA subitamente).
//   2. A lista de páginas (pages) agora é gerada de forma estática e segura.

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../models/usina.dart';
import '../models/lancamento.dart';

import 'usinas_list_screen.dart';
import 'visao_geral_screen.dart';
import 'auditoria_screen.dart';
import '../widgets/app_drawer.dart';
import '../services/sincronizacao_service.dart';
import '../services/dashboard_provider.dart';
import '../services/subscription_provider.dart';
import '../utils/app_feedback.dart';
import '../widgets/responsive_layout.dart';

// Importação das Telas Admin e Operação
import 'admin/meu_plano_screen.dart';
import 'admin/minha_equipe_screen.dart';
import 'admin/historico_atividades_screen.dart';
import 'configuracao_dados_screen.dart';
import 'configuracoes_screen.dart';
import 'paywall_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _paginaAtual = 0;
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // Bloqueia a interface principal até os dados chegarem
  bool _isFirstSyncLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inicializarProcessos();
    });
  }

  void _inicializarProcessos() async {
    final sub = Provider.of<SubscriptionProvider>(context, listen: false);

    await sub.recarregarSessaoCompleta();

    if (!mounted) return;

    if (sub.podeSincronizar()) {
      final boxUsinas = Hive.box<Usina>('usinas');

      if (boxUsinas.isEmpty) {
        debugPrint(
          '📥 [MainNav] Banco vazio. A descarregar dados iniciais da nuvem...',
        );
        await SincronizacaoService().sincronizarTudo();

        if (mounted) {
          Provider.of<DashboardProvider>(context, listen: false).atualizar();
        }
      }

      SincronizacaoService.inicializarMotorReativo();
      debugPrint('✅ [MainNav] Motor reativo iniciado (empresa PRO).');
    } else {
      debugPrint('⏸️️ [MainNav] Empresa grátis. Motor reativo NÃO iniciado.');
    }

    if (mounted) {
      setState(() {
        _isFirstSyncLoading = false;
      });
      _verificarConvitesPendentes();
    }
  }

  Future<void> _executarSyncManual() async {
    final sub = Provider.of<SubscriptionProvider>(context, listen: false);
    if (!sub.podeSincronizar()) {
      if (sub.isAdmin) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PaywallScreen(
              mensagemMotivo:
                  "Sincronização automática entre dispositivos é uma função PRO.",
            ),
          ),
        );
      } else {
        AppFeedback.show(
          context,
          "🔒 Sincronização é uma função PRO. Peça ao administrador para fazer o upgrade.",
          isError: true,
        );
      }
      return;
    }

    try {
      final resultado = await SincronizacaoService().sincronizarTudo();
      if (!mounted) return;

      Provider.of<DashboardProvider>(context, listen: false).atualizar();

      if (resultado.contains('Erro') || resultado.contains('Sem internet')) {
        AppFeedback.show(context, resultado, isError: true);
      } else if (resultado == 'Sincronizado.') {
        AppFeedback.show(context, "Tudo já está sincronizado.", isError: false);
      } else {
        AppFeedback.show(
          context,
          "Dados sincronizados com sucesso!",
          isError: false,
        );
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.show(context, "Erro ao ligar à nuvem.", isError: true);
      }
    }
  }

  void _navegarParaIndice(int index) {
    setState(() {
      _paginaAtual = index;
    });
  }

  Future<void> _verificarConvitesPendentes() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;
    final emailBusca = user.email!.toLowerCase().trim();

    try {
      final snapshot = await _firestore
          .collection('invites')
          .where('email', isEqualTo: emailBusca)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final pendentes = snapshot.docs
            .where((d) => d.data()['status'] == 'pendente')
            .toList();

        if (pendentes.isNotEmpty) {
          final inviteDoc = pendentes.first;
          final inviteData = inviteDoc.data();
          if (mounted) {
            _exibirAlertaConvite(
              inviteDoc.id,
              inviteData['nomeEmpresa'] ?? "Uma nova empresa",
              inviteData['empresaId'],
            );
          }
        }
      }
    } catch (e) {
      debugPrint("Erro ao verificar convites: $e");
    }
  }

  void _exibirAlertaConvite(
    String inviteId,
    String nomeEmpresa,
    String empresaId,
  ) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.business_center,
              color: Colors.deepOrange,
              size: 48,
            ),
            const SizedBox(height: 16),
            const Text(
              "Convite de Equipe",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              "A empresa $nomeEmpresa convidou-o para fazer parte da equipe.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await _firestore
                          .collection('invites')
                          .doc(inviteId)
                          .update({'status': 'recusado'});

                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text("RECUSAR"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _aceitarConvite(inviteId, empresaId),
                    child: const Text("ACEITAR"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _aceitarConvite(String inviteId, String novaEmpresaId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      String planoHerdado = 'gratis';
      String? nomeEmpresaHerdado;

      try {
        final donoDoc = await _firestore
            .collection('users')
            .doc(novaEmpresaId)
            .get();

        if (donoDoc.exists && donoDoc.data() != null) {
          final dadosDono = donoDoc.data() as Map<String, dynamic>;
          planoHerdado = dadosDono['plano'] ?? 'gratis';
          nomeEmpresaHerdado = dadosDono['nomeEmpresa'];
        }
      } catch (e) {
        debugPrint(
          '⚠️ [MainNav] Leitura do dono bloqueada (regras). Fallback aplicado.',
        );
      }

      if (nomeEmpresaHerdado == null) {
        try {
          final inviteDoc = await _firestore
              .collection('invites')
              .doc(inviteId)
              .get();
          if (inviteDoc.exists) {
            nomeEmpresaHerdado = inviteDoc.data()?['nomeEmpresa'];
          }
        } catch (_) {}
      }

      final Map<String, dynamic> update = {
        'empresaId': novaEmpresaId,
        'role': 'user',
        'plano': planoHerdado,
      };
      if (nomeEmpresaHerdado != null && nomeEmpresaHerdado.isNotEmpty) {
        update['nomeEmpresa'] = nomeEmpresaHerdado;
      }

      await _firestore
          .collection('users')
          .doc(user.uid)
          .set(update, SetOptions(merge: true));

      try {
        await _firestore.collection('invites').doc(inviteId).update({
          'status': 'aceito',
          'dataAceite': FieldValue.serverTimestamp(),
          'userId': user.uid,
        });
      } catch (e) {
        debugPrint(
          '⚠️ [MainNav] O status do convite não pôde ser alterado: $e',
        );
      }

      await Hive.box<Usina>('usinas').clear();
      await Hive.box<LancamentoMensal>('lancamentos').clear();

      if (mounted) {
        context.read<DashboardProvider>().atualizar();
        Navigator.pop(context);
        AppFeedback.show(context, "Bem-vindo à equipe!");
      }

      if (mounted) {
        await context.read<SubscriptionProvider>().carregarPlanoDoServidor();
      }

      if (mounted) {
        final sub = context.read<SubscriptionProvider>();
        if (sub.podeSincronizar()) {
          await SincronizacaoService().sincronizarTudo();
        }
      }

      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        AppFeedback.show(context, "Erro de ligação: $e", isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isFirstSyncLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        body: Center(
          child: TweenAnimationBuilder(
            tween: Tween<double>(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: child,
                ),
              );
            },
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 450),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 48,
                  ),
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
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.deepOrange.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.wb_sunny,
                          size: 64,
                          color: Colors.deepOrange,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        "SolarInsight",
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.deepOrange,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Preparando o seu ambiente...",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Verificando credenciais e sincronizando os seus dados com a nuvem de forma segura.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 40),
                      const SizedBox(
                        width: 45,
                        height: 45,
                        child: CircularProgressIndicator(
                          color: Colors.deepOrange,
                          strokeWidth: 4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final List<String> navTitulos = ['Visão Geral', 'Unidades', 'Auditoria'];
    final List<IconData> navIcones = [
      Icons.dashboard_outlined,
      Icons.solar_power_outlined,
      Icons.bar_chart_outlined,
    ];

    final mobileAppBar = AppBar(
      title: const Text(
        'SolarInsight',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 22,
          color: Colors.deepOrange,
        ),
      ),
      centerTitle: false,
      backgroundColor: const Color(0xFFF5F7FA),
      elevation: 0,
      actions: [
        Builder(
          builder: (context) => IconButton(
            icon: const CircleAvatar(
              backgroundColor: Colors.white,
              radius: 18,
              child: Icon(Icons.person, color: Colors.deepOrange, size: 20),
            ),
            onPressed: () => Scaffold.of(context).openEndDrawer(),
          ),
        ),
        const SizedBox(width: 16),
      ],
    );

    // =========================================================================
    // ✅ CORREÇÃO: Remoção dos ValueListenableBuilders (O "Assassino de Foco").
    // As telas agora mantêm o estado independentemente das atualizações de fundo.
    // =========================================================================
    final subProvider = Provider.of<SubscriptionProvider>(context);
    final bool isAdmin = subProvider.isAdmin;

    final acessoRestrito = Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.lock_person_outlined,
              size: 80,
              color: Colors.grey,
            ),
            const SizedBox(height: 24),
            const Text(
              "Área Restrita",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "Não tem permissão para acessar este menu.",
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => setState(() => _paginaAtual = 0),
              child: const Text("VOLTAR AO DASHBOARD"),
            ),
          ],
        ),
      ),
    );

    // ✅ As páginas agora são instanciadas de forma simples e constante,
    // sem as ValueKeys baseadas no tamanho do banco de dados.
    final List<Widget> pages = [
      const VisaoGeralScreen(),
      const UsinasListScreen(),
      const AuditoriaScreen(),
      isAdmin ? const MeuPlanoScreen() : acessoRestrito,
      const MinhaEquipeScreen(),
      isAdmin ? const HistoricoAtividadesScreen() : acessoRestrito,
      isAdmin ? const ConfiguracaoDadosScreen() : acessoRestrito,
      const ConfiguracoesScreen(),
    ];

    return ResponsiveLayout(
      currentIndex: _paginaAtual,
      onTabTapped: _navegarParaIndice,
      pages: pages,
      titulos: navTitulos,
      icones: navIcones,
      mobileAppBar: mobileAppBar,
      mobileDrawer: const AppDrawer(),
      mobileFab: null,
      onSyncTap: _executarSyncManual,
      onAdminItemTap: (index) {
        setState(() => _paginaAtual = index);
      },
    );
  }
}
