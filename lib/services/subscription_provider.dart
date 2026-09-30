// Caminho: lib/services/subscription_provider.dart
// Descrição: Guardião de Limites do Plano (Freemium) com suporte a OFFLINE-FIRST,
//            expiração de cache e Controle de Cargo (Admin/User).
//
// ALTERAÇÕES DESTA VERSÃO:
//   1. PLANO = EMPRESA: o plano agora é lido do DONO da empresa (users/{empresaId}),
//      não do usuário logado. Colaborador herda automaticamente o PRO do dono.
//   2. Novos getters/métodos:
//      - isProEmpresa: o getter que TODOS os bloqueios devem usar.
//      - isDonoDaEmpresa: true se empresaId == uid (é o dono).
//      - podeConvidarColaborador(): só PRO convida.
//      - podeSincronizar(): só PRO sincroniza.
//      - podeUsarIA(): só PRO usa IA.
//   3. Fallback de compatibilidade: se a leitura do dono falhar (rules/rede),
//      usa o próprio plano (comportamento antigo) — nunca quebra.

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'sincronizacao_service.dart'; // ✅ Guard isPaused no logout

class SubscriptionProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ===========================================================================
  // ESTADO INTERNO
  // ===========================================================================
  String _planoAtual = 'gratis';
  String _userRole = 'admin';
  String _empresaId = '';

  // ✅ NOVO: guarda o plano do DONO da empresa (quando o usuário é colaborador)
  String _planoDaEmpresa = 'gratis';

  bool _isLoading = true;

  // ===========================================================================
  // GETTERS PÚBLICOS
  // ===========================================================================
  /// Plano do usuário logado (individual). Mantido para compatibilidade.
  String get planoAtual => _planoAtual;

  /// ⚠️ DEPRECATED: use `isProEmpresa` no lugar.
  /// Mantido para não quebrar código legado. Reflete o mesmo valor.
  bool get isPro => isProEmpresa;

  /// ✅ CORRETO: é PRO porque a EMPRESA é PRO (herdado do dono).
  /// Este é o getter que TODOS os bloqueios de recurso devem usar.
  bool get isProEmpresa => _planoDaEmpresa == 'pro';

  bool get isAdmin => _userRole == 'admin';
  bool get isLoading => _isLoading;

  /// ✅ NOVO: indica se o usuário logado é o DONO da empresa.
  /// Útil para decidir se ele pode fazer upgrade, convidar, etc.
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
    _inicializarGuardiao();
  }

  // ===========================================================================
  // RESET (para uso no logout)
  // ===========================================================================
  void reset() {
    _planoAtual = 'gratis';
    _userRole = 'admin';
    _empresaId = '';
    _planoDaEmpresa = 'gratis';
    _isLoading = true;
    notifyListeners();
  }

  Future<void> _inicializarGuardiao() async {
    await _carregarPlanoDoCacheLocal();
    await carregarPlanoDoServidor();
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

      // ✅ NOVO: carrega também o plano da empresa do cache
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

      // Aplica a expiração do "visto" offline sobre o plano da EMPRESA
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
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ===========================================================================
  // LEITURA ONLINE (FIRESTORE) — Lê do DONO da empresa
  // ===========================================================================
  Future<void> carregarPlanoDoServidor() async {
    User? user = _auth.currentUser;
    if (user == null) return;

    // Guard de logout (evita permission-denied durante transição de sessão)
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
      // 1. Lê meu próprio doc para descobrir empresaId, role e meu plano individual
      DocumentSnapshot meuDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();

      if (!meuDoc.exists || meuDoc.data() == null) return;

      final meusDados = meuDoc.data() as Map<String, dynamic>;
      _userRole = meusDados['role'] ?? 'admin';
      _planoAtual = meusDados['plano'] ?? 'gratis';
      _empresaId = meusDados['empresaId'] ?? user.uid;

      // 2. Descobre de onde ler o plano da EMPRESA
      String planoDaEmpresa;

      if (_empresaId == user.uid) {
        // Sou o dono → o plano da empresa é o MEU plano
        planoDaEmpresa = _planoAtual;
        debugPrint(
          "👑 [Subscription] Sou o DONO. Plano da empresa = meu plano = $planoDaEmpresa",
        );
      } else {
        // Sou colaborador → leio o plano do DONO (doc users/{empresaId})
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
            // Doc do dono não existe (raro) → fallback para meu próprio plano
            planoDaEmpresa = _planoAtual;
            debugPrint(
              "⚠️ [Subscription] Doc do dono não existe. Fallback: $planoDaEmpresa",
            );
          }
        } catch (e) {
          // Falha na leitura cross-user (rules, rede) → fallback
          planoDaEmpresa = _planoAtual;
          debugPrint(
            "⚠️ [Subscription] Falha ao ler dono ($e). Fallback: $planoDaEmpresa",
          );
        }
      }

      _planoDaEmpresa = planoDaEmpresa;

      // 3. Persiste no cache local (offline-first)
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
      // permission-denied é esperado durante transições de sessão
      if (e.code == 'permission-denied') {
        debugPrint(
          '🔇 [Subscription] permission-denied ignorado (transição de sessão).',
        );
      } else {
        debugPrint("Erro ao buscar plano no servidor: $e");
      }
    } catch (e) {
      debugPrint("Erro ao buscar plano no servidor: $e");
    } finally {
      notifyListeners();
    }
  }

  // ===========================================================================
  // MÉTODOS DE CHECAGEM (todos usam isProEmpresa agora)
  // ===========================================================================

  /// ✅ Usinas geradoras: grátis = 1, PRO = ∞.
  bool podeAdicionarUsinaGeradora(int totalGeradorasAtuais) {
    if (isProEmpresa) return true;
    return totalGeradorasAtuais < limiteUsinasGeradorasGratis;
  }

  /// ✅ Usinas filhas: grátis = 2, PRO = ∞.
  bool podeAdicionarUsinaFilha(int totalFilhasAtuais) {
    if (isProEmpresa) return true;
    return totalFilhasAtuais < limiteUsinasFilhasGratis;
  }

  /// ✅ NOVO: colaboradores só no PRO.
  bool podeConvidarColaborador() {
    return isProEmpresa;
  }

  /// ✅ NOVO: sync só no PRO.
  bool podeSincronizar() {
    return isProEmpresa;
  }

  /// ✅ NOVO: IA só no PRO.
  bool podeUsarIA() {
    return isProEmpresa;
  }

  // ===========================================================================
  // ATUALIZAÇÃO FORÇADA (após compra simulada ou restore)
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
