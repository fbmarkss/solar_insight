// Caminho: lib/services/subscription_provider.dart
// ALTERAÇÃO: Adicionado método reset() para limpeza total no logout.

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class SubscriptionProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _planoAtual = 'gratis';
  String _userRole = 'admin';
  bool _isLoading = true;

  String get planoAtual => _planoAtual;
  bool get isPro => _planoAtual == 'pro';
  bool get isAdmin => _userRole == 'admin';
  bool get isLoading => _isLoading;

  static const int limiteUsinasGeradorasGratis = 1;
  static const int limiteUsinasFilhasGratis = 2;
  static const Duration validadeCacheOffline = Duration(days: 15);

  SubscriptionProvider() {
    _inicializarGuardiao();
  }

  // ===========================================================================
  // RESET (para uso no logout)
  // ===========================================================================
  /// Zera o estado para os valores padrão. Chamado pelo SessionManager no logout.
  /// Nota: NÃO apaga o 'auth_cache' do Hive — quem faz isso é o SessionManager.
  void reset() {
    _planoAtual = 'gratis';
    _userRole = 'admin';
    _isLoading = true;
    notifyListeners();
  }

  Future<void> _inicializarGuardiao() async {
    await _carregarPlanoDoCacheLocal();
    await carregarPlanoDoServidor();
  }

  Future<void> _carregarPlanoDoCacheLocal() async {
    try {
      // ⚠️ PROTEÇÃO: garante que a box está aberta
      if (!Hive.isBoxOpen('auth_cache')) {
        await Hive.openBox('auth_cache');
      }
      var box = Hive.box('auth_cache');

      String planoSalvo = box.get('plano_salvo', defaultValue: 'gratis');
      String roleSalva = box.get('role_salva', defaultValue: 'admin');
      DateTime? ultimaVerificacao = box.get('data_verificacao');

      _userRole = roleSalva;

      if (planoSalvo == 'pro' && ultimaVerificacao != null) {
        final tempoPassado = DateTime.now().difference(ultimaVerificacao);

        if (tempoPassado > validadeCacheOffline) {
          debugPrint("🚫 Visto offline PRO expirado. Rebaixando para grátis.");
          _planoAtual = 'gratis';
        } else {
          debugPrint(
            "✅ Visto offline PRO válido. Tempo passado: ${tempoPassado.inDays} dias.",
          );
          _planoAtual = 'pro';
        }
      } else {
        _planoAtual = planoSalvo;
      }
    } catch (e) {
      debugPrint("Erro ao ler cache offline: $e");
      _planoAtual = 'gratis';
      _userRole = 'user';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> carregarPlanoDoServidor() async {
    User? user = _auth.currentUser;
    if (user == null) return;

    final List<ConnectivityResult> connectivityResult = await (Connectivity()
        .checkConnectivity());
    if (connectivityResult.contains(ConnectivityResult.none)) {
      debugPrint(
        "📡 Sem internet. Mantendo o plano do cache local: $_planoAtual",
      );
      return;
    }

    try {
      DocumentSnapshot doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        String planoNoServidor = data['plano'] ?? 'gratis';
        String roleNoServidor = data['role'] ?? 'admin';

        _planoAtual = planoNoServidor;
        _userRole = roleNoServidor;

        // ⚠️ PROTEÇÃO: garante box aberta
        if (!Hive.isBoxOpen('auth_cache')) {
          await Hive.openBox('auth_cache');
        }
        var box = Hive.box('auth_cache');
        await box.put('plano_salvo', planoNoServidor);
        await box.put('role_salva', roleNoServidor);
        await box.put('data_verificacao', DateTime.now());

        debugPrint("📡 Servidor: Plano $_planoAtual | Role: $_userRole");
      }
    } catch (e) {
      debugPrint("Erro ao buscar plano no servidor: $e");
    } finally {
      notifyListeners();
    }
  }

  bool podeAdicionarUsinaGeradora(int totalGeradorasAtuais) {
    if (isPro) return true;
    return totalGeradorasAtuais < limiteUsinasGeradorasGratis;
  }

  bool podeAdicionarUsinaFilha(int totalFilhasAtuais) {
    if (isPro) return true;
    return totalFilhasAtuais < limiteUsinasFilhasGratis;
  }

  void atualizarPlanoForcado(String novoPlano) async {
    _planoAtual = novoPlano;

    if (!Hive.isBoxOpen('auth_cache')) {
      await Hive.openBox('auth_cache');
    }
    var box = Hive.box('auth_cache');
    await box.put('plano_salvo', novoPlano);
    await box.put('data_verificacao', DateTime.now());

    notifyListeners();
  }
}
