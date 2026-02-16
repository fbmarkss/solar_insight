// Caminho: lib/screens/main_navigation_screen.dart
// Descrição: Controlador mestre (Single Page Application na Web, Navegação Híbrida).
// ATUALIZAÇÃO: Removido o FAB global de todas as abas. Cada tela gere o seu próprio botão.

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
import '../utils/app_feedback.dart';
import '../widgets/responsive_layout.dart';

// Importação das Telas Admin
import 'admin/meu_plano_screen.dart';
import 'admin/minha_equipe_screen.dart';
import 'admin/historico_atividades_screen.dart';
import 'configuracao_dados_screen.dart';
import 'configuracoes_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _paginaAtual = 0; // Índice que controla o conteúdo central
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _inicializarProcessos();
  }

  void _inicializarProcessos() async {
    _sincronizacaoAutomatica();
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) _verificarConvitesPendentes();
  }

  void _sincronizacaoAutomatica() async {
    try {
      await SincronizacaoService().sincronizarTudo();
    } catch (e) {
      debugPrint("Auto Sync falhou: $e");
    }
  }

  Future<void> _executarSyncManual() async {
    AppFeedback.show(context, "Sincronizando dados...");
    try {
      final resultado = await context
          .read<DashboardProvider>()
          .sincronizarDados();
      if (mounted) {
        if (resultado.contains('Erro')) {
          AppFeedback.show(context, resultado, isError: true);
        } else {
          AppFeedback.show(context, "Sincronização concluída!");
        }
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.show(context, "Erro ao sincronizar.", isError: true);
      }
    }
  }

  // --- NOVA LÓGICA DE NAVEGAÇÃO INTERNA (WEB) ---
  // Ao invés de abrir nova tela, apenas trocamos o índice da lista de páginas
  void _navegarParaIndice(int index) {
    setState(() {
      _paginaAtual = index;
    });
  }

  // --- LÓGICA DE CONVITES ---
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
          final String nomeEmpresa =
              inviteData['nomeEmpresa'] ?? "Uma nova empresa";
          final String novaEmpresaId = inviteData['empresaId'];

          if (mounted) {
            _exibirAlertaConvite(inviteDoc.id, nomeEmpresa, novaEmpresaId);
          }
        }
      }
    } catch (e) {
      debugPrint("Erro ao checar convites: $e");
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
              "A empresa $nomeEmpresa convidou você para fazer parte da equipe.",
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
                      if (mounted) Navigator.pop(ctx);
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
      await _firestore.collection('users').doc(user.uid).update({
        'empresaId': novaEmpresaId,
        'role': 'user',
      });
      await _firestore.collection('invites').doc(inviteId).update({
        'status': 'aceito',
        'dataAceite': FieldValue.serverTimestamp(),
        'userId': user.uid,
      });

      await Hive.box<Usina>('usinas').clear();
      await Hive.box<LancamentoMensal>('lancamentos').clear();

      if (mounted) {
        context.read<DashboardProvider>().atualizar();
        Navigator.pop(context);
        AppFeedback.show(context, "Bem-vindo à nova equipe! Sincronizando...");
      }

      await SincronizacaoService().sincronizarTudo();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        AppFeedback.show(context, "Erro ao aceitar convite.", isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<String> navTitulos = ['Visão Geral', 'Usinas', 'Auditoria'];
    final List<IconData> navIcones = [
      Icons.dashboard_outlined,
      Icons.solar_power_outlined,
      Icons.bar_chart_outlined,
    ];

    // AppBar Comum (Mobile)
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
        IconButton(
          icon: const Icon(Icons.sync, color: Colors.deepOrange),
          onPressed: _executarSyncManual,
        ),
        const SizedBox(width: 8),
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

    // MÁGICA: Não passamos NENHUM FAB Global para o ResponsiveLayout.
    // Cada tela (Visão Geral, Usinas, etc) vai desenhar e gerir o seu próprio botão,
    // garantindo que ele respeita a arquitetura correta (Web vs Mobile e Gaiola Aninhada).

    return ValueListenableBuilder(
      valueListenable: Hive.box<Usina>('usinas').listenable(),
      builder: (context, boxUsinas, _) {
        return ValueListenableBuilder(
          valueListenable: Hive.box<LancamentoMensal>(
            'lancamentos',
          ).listenable(),
          builder: (context, boxLancamentos, _) {
            final String refreshKey =
                "${boxUsinas.length}_${boxLancamentos.length}";

            // --- LISTA UNIFICADA DE TELAS ---
            // Agora todas as telas vivem aqui, permitindo a troca sem Navigation.push na Web
            final List<Widget> pages = [
              // 0: Visão Geral
              VisaoGeralScreen(key: ValueKey("visao_$refreshKey")),
              // 1: Lista de Usinas
              UsinasListScreen(key: ValueKey("list_$refreshKey")),
              // 2: Auditoria
              AuditoriaScreen(key: ValueKey("audit_$refreshKey")),

              // --- TELAS ADMIN (Indices 3 a 7) ---
              const MeuPlanoScreen(), // 3
              const MinhaEquipeScreen(), // 4
              const HistoricoAtividadesScreen(), // 5
              const ConfiguracaoDadosScreen(), // 6
              const ConfiguracoesScreen(), // 7
            ];

            return ResponsiveLayout(
              currentIndex: _paginaAtual,
              onTabTapped: _navegarParaIndice, // Para abas principais (0-2)
              pages: pages,
              titulos: navTitulos,
              icones: navIcones,

              // Parâmetros Mobile
              mobileAppBar: mobileAppBar,
              mobileDrawer: const AppDrawer(),
              mobileFab: null, // Deixamos as telas tratarem disso internamente
              // Callbacks Web
              onSyncTap: _executarSyncManual,
              onAdminItemTap: (index) {
                // Ao clicar no menu admin da web, apenas trocamos o índice!
                // O ResponsiveLayout já renderiza a página correspondente no centro.
                setState(() => _paginaAtual = index);
              },
            );
          },
        );
      },
    );
  }
}
