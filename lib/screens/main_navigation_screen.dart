// Caminho: lib/screens/main_navigation_screen.dart
// Descrição: Controlador mestre (Single Page Application na Web, Navegação Híbrida).
//
// ALTERAÇÕES DESTA VERSÃO:
//   1. _inicializarProcessos() só inicia o motor reativo se a EMPRESA for PRO.
//      No grátis, o motor nem começa (economia de bateria + zero tentativas
//      de sync bloqueado).
//   2. _executarSyncManual() tem guard defensivo: se grátis, abre Paywall.
//   3. _aceitarConvite() agora herda 'plano' + 'nomeEmpresa' do dono ao
//      vincular o usuário à nova empresa. Corrige o caso do usuário que
//      JÁ EXISTE e aceita um convite pendente (auth_service.cadastrar não
//      é chamado nesse fluxo).
//   4. Todo o resto permanece intacto.

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

  @override
  void initState() {
    super.initState();
    _inicializarProcessos();
  }

  void _inicializarProcessos() async {
    // ✅ Aguarda o SubscriptionProvider resolver o plano da empresa
    // (evita falso-negativo no cold start)
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    final sub = Provider.of<SubscriptionProvider>(context, listen: false);
    if (sub.podeSincronizar()) {
      SincronizacaoService.inicializarMotorReativo();
      debugPrint('✅ [MainNav] Motor reativo iniciado (empresa PRO).');
    } else {
      debugPrint('⏸️ [MainNav] Empresa grátis. Motor reativo NÃO iniciado.');
    }

    await Future.delayed(const Duration(seconds: 1));
    if (mounted) _verificarConvitesPendentes();
  }

  Future<void> _executarSyncManual() async {
    // ✅ GUARD DEFENSIVO: se grátis, abre Paywall em vez de sincronizar
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
        AppFeedback.show(
          context,
          "Erro ao conectar com a nuvem.",
          isError: true,
        );
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
      // =======================================================================
      // ✅ HERANÇA: busca o plano + nomeEmpresa do DONO antes de atualizar
      // =======================================================================
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
          debugPrint(
            '🤝 [MainNav] Herdando do dono: plano=$planoHerdado | nome=$nomeEmpresaHerdado',
          );
        }
      } catch (e) {
        debugPrint('⚠️ [MainNav] Falha ao ler dono (fallback gratis): $e');
      }

      // =======================================================================
      // Atualiza o doc do usuário com herança
      // =======================================================================
      final Map<String, dynamic> update = {
        'empresaId': novaEmpresaId,
        'role': 'user',
        'plano': planoHerdado, // ✅ herda
      };
      if (nomeEmpresaHerdado != null && nomeEmpresaHerdado.isNotEmpty) {
        update['nomeEmpresa'] = nomeEmpresaHerdado; // ✅ herda
      }

      await _firestore.collection('users').doc(user.uid).update(update);

      // Marca o convite como aceito
      await _firestore.collection('invites').doc(inviteId).update({
        'status': 'aceito',
        'dataAceite': FieldValue.serverTimestamp(),
        'userId': user.uid,
      });

      // Limpa dados locais do usuário anterior (muda de contexto de empresa)
      await Hive.box<Usina>('usinas').clear();
      await Hive.box<LancamentoMensal>('lancamentos').clear();

      if (mounted) {
        context.read<DashboardProvider>().atualizar();
        Navigator.pop(context);
        AppFeedback.show(context, "Bem-vindo à nova equipe!");
      }

      // ✅ Recarrega o plano (agora herda o do dono)
      if (mounted) {
        await context.read<SubscriptionProvider>().carregarPlanoDoServidor();
      }

      // ✅ Se a nova empresa for PRO, tenta sincronizar; se não, avisa
      if (mounted) {
        final sub = context.read<SubscriptionProvider>();
        if (sub.podeSincronizar()) {
          await SincronizacaoService().sincronizarTudo();
        }
      }

      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        AppFeedback.show(context, "Erro ao aceitar convite.", isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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

    // --- CADEADO MESTRA: Busca Permissões do Usuário ---
    return FutureBuilder<DocumentSnapshot>(
      future: _auth.currentUser != null
          ? _firestore.collection('users').doc(_auth.currentUser!.uid).get()
          : null,
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Colors.deepOrange),
            ),
          );
        }

        final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
        final bool isAdmin = userData?['role'] == 'admin';

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
                  "Você não tem permissão para acessar este menu.",
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

                final List<Widget> pages = [
                  VisaoGeralScreen(key: ValueKey("visao_$refreshKey")), // 0
                  UsinasListScreen(key: ValueKey("list_$refreshKey")), // 1
                  AuditoriaScreen(key: ValueKey("audit_$refreshKey")), // 2
                  isAdmin ? const MeuPlanoScreen() : acessoRestrito, // 3
                  const MinhaEquipeScreen(), // 4
                  isAdmin
                      ? const HistoricoAtividadesScreen()
                      : acessoRestrito, // 5
                  isAdmin
                      ? const ConfiguracaoDadosScreen()
                      : acessoRestrito, // 6
                  const ConfiguracoesScreen(), // 7
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
              },
            );
          },
        );
      },
    );
  }
}
