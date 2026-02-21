// Caminho: lib/services/subscription_provider.dart
// Descrição: Guardião de Limites do Plano (Freemium) com suporte a OFFLINE-FIRST, expiração de cache e Controle de Cargo (Admin/User).

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class SubscriptionProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _planoAtual = 'gratis';
  String _userRole = 'admin'; // <-- NOVO: Controle de cargo
  bool _isLoading = true;

  // --- GETTERS ---
  String get planoAtual => _planoAtual;
  bool get isPro => _planoAtual == 'pro';
  bool get isAdmin =>
      _userRole == 'admin'; // <-- NOVO: Verifica se é o dono da conta
  bool get isLoading => _isLoading;

  // --- LIMITES DO PLANO GRÁTIS ---
  static const int limiteUsinasGeradorasGratis = 1;
  static const int limiteUsinasFilhasGratis = 2;
  // Tempo máximo que o app confia no status PRO offline antes de exigir internet
  static const Duration validadeCacheOffline = Duration(days: 15);

  SubscriptionProvider() {
    _inicializarGuardiao();
  }

  Future<void> _inicializarGuardiao() async {
    // 1. Tenta carregar o plano guardado localmente (Offline) para o app abrir rápido
    await _carregarPlanoDoCacheLocal();

    // 2. Tenta conectar na internet para pegar a versão mais nova do servidor
    await carregarPlanoDoServidor();
  }

  // --- LEITURA OFFLINE (HIVE) ---
  Future<void> _carregarPlanoDoCacheLocal() async {
    try {
      var box = await Hive.openBox('auth_cache');
      String planoSalvo = box.get('plano_salvo', defaultValue: 'gratis');
      String roleSalva = box.get(
        'role_salva',
        defaultValue: 'admin',
      ); // <-- LER CARGO OFFLINE
      DateTime? ultimaVerificacao = box.get('data_verificacao');

      _userRole = roleSalva; // Guarda na memória

      // Se for PRO no cache, precisamos ver se o "Visto" não expirou
      if (planoSalvo == 'pro' && ultimaVerificacao != null) {
        final tempoPassado = DateTime.now().difference(ultimaVerificacao);

        if (tempoPassado > validadeCacheOffline) {
          // O visto expirou! Rebaixamos para grátis até ele ligar a internet
          debugPrint("🚫 Visto offline PRO expirado. Rebaixando para grátis.");
          _planoAtual = 'gratis';
        } else {
          // Visto válido. Pode usar offline!
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
      _userRole = 'user'; // Por segurança restringe se der erro
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- LEITURA ONLINE (FIRESTORE) ---
  Future<void> carregarPlanoDoServidor() async {
    User? user = _auth.currentUser;
    if (user == null) return;

    // Verifica se tem internet antes de tentar o Firebase
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
        String roleNoServidor =
            data['role'] ?? 'admin'; // <-- BUSCA CARGO NO SERVIDOR

        // Atualiza a memória
        _planoAtual = planoNoServidor;
        _userRole = roleNoServidor;

        // Atualiza o "Visto" offline no Hive com a data de hoje
        var box = await Hive.openBox('auth_cache');
        await box.put('plano_salvo', planoNoServidor);
        await box.put('role_salva', roleNoServidor); // <-- SALVA CARGO OFFLINE
        await box.put('data_verificacao', DateTime.now());

        debugPrint("📡 Servidor: Plano $_planoAtual | Role: $_userRole");
      }
    } catch (e) {
      debugPrint("Erro ao buscar plano no servidor: $e");
    } finally {
      notifyListeners();
    }
  }

  // --- REGRAS DE BLOQUEIO NAS TELAS ---
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

    // Atualiza o cache offline imediatamente quando ele compra
    var box = await Hive.openBox('auth_cache');
    await box.put('plano_salvo', novoPlano);
    await box.put('data_verificacao', DateTime.now());

    notifyListeners();
  }
}
