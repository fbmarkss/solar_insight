// Caminho: lib/services/subscription_provider.dart
// Descrição: Guardião de Limites do Plano (Freemium) com suporte a OFFLINE-FIRST,
//            expiração de cache e Controle de Cargo (Admin/User).
//
// ALTERAÇÕES DESTA VERSÃO:
//   1. Criação do método recarregarSessaoCompleta() para forçar o bloqueio da UI
//      (mantendo _isLoading = true) até que o Firebase responda com o plano real.
//   2. Correção da Race Condition: A tela principal agora pode ter certeza de que,
//      quando isLoading for false, o plano PRO ou Grátis é o definitivo.

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'sincronizacao_service.dart';

class SubscriptionProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ===========================================================================
  // ESTADO INTERNO
  // ===========================================================================
  String _planoAtual = 'gratis';
  String _userRole = 'admin';
  String _empresaId = '';
  String _planoDaEmpresa = 'gratis';

  bool _isLoading = true;

  // ===========================================================================
  // GETTERS PÚBLICOS
  // ===========================================================================
  String get planoAtual => _planoAtual;
  bool get isPro => isProEmpresa;
  bool get isProEmpresa => _planoDaEmpresa == 'pro';
  bool get isAdmin => _userRole == 'admin';
  bool get isLoading => _isLoading;

  bool get isDonoDaEmpresa {
    final uid = _auth.currentUser?.uid;
    return uid != null && _empresaId == uid;
  }

  // ===========================================================================
  // LIMITES DO PLANO GRÁTIS
  // ===========================================================================
  static const int limiteUsinasGeradorasGratis = 1;
  static const int limiteUsinasFilhasGratis = 2;
  static const Duration validadeCacheOffline = Duration(days: 15);

  SubscriptionProvider() {
    // Ao nascer, dispara o carregamento inicial silencioso
    recarregarSessaoCompleta();
  }

  // ===========================================================================
  // RESET (para uso no logout)
  // ===========================================================================
  void reset() {
    _planoAtual = 'gratis';
    _userRole = 'admin';
    _empresaId = '';
    _planoDaEmpresa = 'gratis';
    // _isLoading não precisa travar a tela de login. O recarregarSessaoCompleta
    // assumirá o controle no próximo login.
    notifyListeners();
  }

  // ===========================================================================
  // CARREGAMENTO BLINDADO (NOVO)
  // ===========================================================================
  /// Executa o ciclo completo (Cache -> Servidor) travando a flag _isLoading
  /// para evitar que o MainNavigation construa a tela antes da resposta da nuvem.
  Future<void> recarregarSessaoCompleta() async {
    _isLoading = true;
    notifyListeners();

    await _carregarPlanoDoCacheLocal();
    await carregarPlanoDoServidor();

    _isLoading = false;
    notifyListeners();
  }

  // ===========================================================================
  // LEITURA OFFLINE (HIVE)
  // ===========================================================================
  Future<void> _carregarPlanoDoCacheLocal() async {
    try {
      if (!Hive.isBoxOpen('auth_cache')) {
        await Hive.openBox('auth_cache');
      }
      var box = Hive.box('auth_cache');

      String planoSalvo = box.get('plano_salvo', defaultValue: 'gratis');
      String roleSalva = box.get('role_salva', defaultValue: 'admin');
      String planoEmpresaSalvo = box.get(
        'plano_empresa_salvo',
        defaultValue: 'gratis',
      );
      String empresaIdSalvo = box.get('empresa_id_salva', defaultValue: '');
      DateTime? ultimaVerificacao = box.get('data_verificacao');

      _userRole = roleSalva;
      _planoAtual = planoSalvo;
      _planoDaEmpresa = planoEmpresaSalvo;
      _empresaId = empresaIdSalvo;

      // Aplica a expiração do "visto" offline
      if (planoEmpresaSalvo == 'pro' && ultimaVerificacao != null) {
        final tempoPassado = DateTime.now().difference(ultimaVerificacao);

        if (tempoPassado > validadeCacheOffline) {
          debugPrint(
            "🚫 Visto offline PRO (empresa) expirado. Rebaixando para grátis.",
          );
          _planoDaEmpresa = 'gratis';
        } else {
          debugPrint(
            "✅ Visto offline PRO (empresa) válido. Dias: ${tempoPassado.inDays}.",
          );
          _planoDaEmpresa = 'pro';
        }
      }
    } catch (e) {
      debugPrint("Erro ao ler cache offline: $e");
      _planoAtual = 'gratis';
      _planoDaEmpresa = 'gratis';
      _userRole = 'user';
    }
    // IMPORTANTE: Removemos o _isLoading = false daqui! Ele só fica falso no final do recarregarSessaoCompleta.
  }

  // ===========================================================================
  // LEITURA ONLINE (FIRESTORE) — Lê do DONO da empresa
  // ===========================================================================
  Future<void> carregarPlanoDoServidor() async {
    User? user = _auth.currentUser;
    if (user == null) return;

    if (SincronizacaoService.isPaused) {
      debugPrint(
        '⏸️ [Subscription] Sync pausado (logout em curso). Pulando leitura.',
      );
      return;
    }

    final List<ConnectivityResult> connectivityResult = await (Connectivity()
        .checkConnectivity());
    if (connectivityResult.contains(ConnectivityResult.none)) {
      debugPrint(
        "📡 Sem internet. Mantendo o plano do cache local: $_planoDaEmpresa",
      );
      return;
    }

    try {
      DocumentSnapshot meuDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();

      if (!meuDoc.exists || meuDoc.data() == null) return;

      final meusDados = meuDoc.data() as Map<String, dynamic>;
      _userRole = meusDados['role'] ?? 'admin';
      _planoAtual = meusDados['plano'] ?? 'gratis';
      _empresaId = meusDados['empresaId'] ?? user.uid;

      String planoDaEmpresa;

      if (_empresaId == user.uid) {
        planoDaEmpresa = _planoAtual;
        debugPrint(
          "👑 [Subscription] Sou o DONO. Plano da empresa = meu plano = $planoDaEmpresa",
        );
      } else {
        try {
          DocumentSnapshot donoDoc = await _firestore
              .collection('users')
              .doc(_empresaId)
              .get();

          if (donoDoc.exists && donoDoc.data() != null) {
            final dadosDono = donoDoc.data() as Map<String, dynamic>;
            planoDaEmpresa = dadosDono['plano'] ?? 'gratis';
            debugPrint(
              "🤝 [Subscription] Sou COLABORADOR. Plano do dono = $planoDaEmpresa",
            );
          } else {
            planoDaEmpresa = _planoAtual;
            debugPrint(
              "⚠️ [Subscription] Doc do dono não existe. Fallback: $planoDaEmpresa",
            );
          }
        } catch (e) {
          planoDaEmpresa = _planoAtual;
          debugPrint(
            "⚠️ [Subscription] Falha ao ler dono ($e). Fallback: $planoDaEmpresa",
          );
        }
      }

      _planoDaEmpresa = planoDaEmpresa;

      // Persiste no cache
      if (!Hive.isBoxOpen('auth_cache')) {
        await Hive.openBox('auth_cache');
      }
      var box = Hive.box('auth_cache');
      await box.put('plano_salvo', _planoAtual);
      await box.put('role_salva', _userRole);
      await box.put('plano_empresa_salvo', _planoDaEmpresa);
      await box.put('empresa_id_salva', _empresaId);
      await box.put('data_verificacao', DateTime.now());

      debugPrint(
        "📡 Servidor: meu plano=$_planoAtual | plano da empresa=$_planoDaEmpresa | role=$_userRole",
      );
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        debugPrint(
          '🔇 [Subscription] permission-denied ignorado (transição de sessão).',
        );
      } else {
        debugPrint("Erro ao buscar plano no servidor: $e");
      }
    } catch (e) {
      debugPrint("Erro ao buscar plano no servidor: $e");
    }
  }

  // ===========================================================================
  // MÉTODOS DE CHECAGEM
  // ===========================================================================
  bool podeAdicionarUsinaGeradora(int totalGeradorasAtuais) {
    if (isProEmpresa) return true;
    return totalGeradorasAtuais < limiteUsinasGeradorasGratis;
  }

  bool podeAdicionarUsinaFilha(int totalFilhasAtuais) {
    if (isProEmpresa) return true;
    return totalFilhasAtuais < limiteUsinasFilhasGratis;
  }

  bool podeConvidarColaborador() => isProEmpresa;
  bool podeSincronizar() => isProEmpresa;
  bool podeUsarIA() => isProEmpresa;

  // ===========================================================================
  // ATUALIZAÇÃO FORÇADA
  // ===========================================================================
  void atualizarPlanoForcado(String novoPlano) async {
    _planoAtual = novoPlano;
    _planoDaEmpresa = novoPlano;

    if (!Hive.isBoxOpen('auth_cache')) {
      await Hive.openBox('auth_cache');
    }
    var box = Hive.box('auth_cache');
    await box.put('plano_salvo', novoPlano);
    await box.put('plano_empresa_salvo', novoPlano);
    await box.put('data_verificacao', DateTime.now());

    notifyListeners();
  }
}
