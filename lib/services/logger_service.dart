// Caminho: lib/services/logger_service.dart
// Descrição: Serviço de registro de logs de atividade no Firestore para auditoria com suporte Híbrido (Stream/Future).
// ALTERAÇÃO DESTA VERSÃO:
//   - Campo 'plataforma' agora é dinâmico (web/android/ios/windows/macos/linux)
//     em vez do valor fixo 'mobile' que existia antes.
//   - Nenhuma outra função foi alterada.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kIsWeb, defaultTargetPlatform, TargetPlatform;

class LoggerService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Registra uma ação no Firestore para auditoria vinculada à empresa.
  Future<void> logAction(String acao, String detalhes) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final String empresaId = userDoc.data()?['empresaId'] ?? user.uid;

      await _firestore.collection('activity_logs').add({
        'uid': user.uid,
        'empresaId': empresaId,
        'usuarioNome': user.displayName ?? 'Usuário sem nome',
        'usuarioEmail': user.email,
        'acao': acao.toUpperCase(),
        'detalhes': detalhes,
        'dataHora': FieldValue.serverTimestamp(),
        // ✅ Agora registra corretamente onde a ação foi executada.
        'plataforma': _plataformaAtual(),
      });
    } catch (e) {
      debugPrint("🧹 Erro ao gravar log de atividade: $e");
    }
  }

  /// RESTAURAÇÃO: Recupera os logs em TEMPO REAL (Para uso na tela de Histórico)
  Stream<QuerySnapshot> getLogs() async* {
    final user = _auth.currentUser;
    if (user == null) return;

    // Busca o perfil uma única vez para pegar o empresaId
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final String empresaId = userDoc.data()?['empresaId'] ?? user.uid;

    yield* _firestore
        .collection('activity_logs')
        .where('empresaId', isEqualTo: empresaId)
        .orderBy('dataHora', descending: true)
        .limit(100)
        .snapshots();
  }

  /// Busca ÚNICA (Para evitar Listeners persistentes onde não é necessário)
  Future<List<DocumentSnapshot>> getLogsOnce() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final String empresaId = userDoc.data()?['empresaId'] ?? user.uid;

      final snapshot = await _firestore
          .collection('activity_logs')
          .where('empresaId', isEqualTo: empresaId)
          .orderBy('dataHora', descending: true)
          .limit(100)
          .get();

      return snapshot.docs;
    } catch (e) {
      debugPrint("Erro ao buscar logs (Once): $e");
      return [];
    }
  }

  // ===========================================================================
  // HELPER: detecta a plataforma atual do runtime
  // ===========================================================================
  String _plataformaAtual() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
        return 'linux';
      default:
        return 'unknown';
    }
  }
}
