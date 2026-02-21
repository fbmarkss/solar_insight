// Caminho: lib/services/auth_service.dart
// Descrição: Serviço de Autenticação com Warm-up de permissões e Cadastro Inteligente (Freemium).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  // --- LOGIN COM WARM-UP DE PERMISSÕES ---
  Future<String?> login(String email, String password) async {
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      User? user = userCredential.user;
      if (user != null) {
        final userDoc = await _firestore
            .collection('users')
            .doc(user.uid)
            .get();

        if (!userDoc.exists) {
          return "Perfil não encontrado. Entre em contato com o administrador.";
        }

        await _firestore.collection('users').doc(user.uid).update({
          'lastSync': FieldValue.serverTimestamp(),
        });

        debugPrint(
          '🔓 Login realizado e permissões validadas para o UID: ${user.uid}',
        );
      }
      return null;
    } on FirebaseAuthException catch (e) {
      return _traduzirErro(e.code);
    } catch (e) {
      return "Erro inesperado: $e";
    }
  }

  // --- CADASTRO INTELIGENTE (RESTAURADO E PROTEGIDO COM PLANO) ---
  Future<String?> cadastrar(String nome, String email, String password) async {
    try {
      final emailLimpo = email.trim().toLowerCase();

      // 1. PRIMEIRO cria o usuário no Auth para garantir permissão de leitura logada
      UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(
            email: emailLimpo,
            password: password,
          );

      User? user = userCredential.user;
      if (user == null) return "Erro ao criar credenciais.";

      await user.updateDisplayName(nome);

      // 2. BUSCA DE CONVITE (Operação protegida)
      String roleDefinida = 'admin';
      String? empresaIdVinculada;
      DocumentSnapshot? conviteDoc;

      try {
        // Consulta simplificada para evitar erro de índice e permissão
        final conviteSnapshot = await _firestore
            .collection('invites')
            .where('email', isEqualTo: emailLimpo)
            .get();

        if (conviteSnapshot.docs.isNotEmpty) {
          // Filtramos o status "pendente" localmente para evitar complexidade no Firestore
          final pendentes = conviteSnapshot.docs
              .where((d) => d.data()['status'] == 'pendente')
              .toList();

          if (pendentes.isNotEmpty) {
            roleDefinida = 'user';
            conviteDoc = pendentes.first;
            final dadosConvite = conviteDoc.data() as Map<String, dynamic>;
            empresaIdVinculada =
                dadosConvite['empresaId'] ?? dadosConvite['invitedBy'];
          }
        }
      } catch (e) {
        debugPrint("Aviso: Falha silenciosa ao checar convites: $e");
        // Em caso de erro na busca, prosseguimos como admin para não travar o usuário
      }

      String finalEmpresaId = empresaIdVinculada ?? user.uid;

      // 3. SALVA PERFIL NO FIRESTORE COM A NOVA ETIQUETA "GRATIS"
      await _firestore.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'nome': nome,
        'email': emailLimpo,
        'createdAt': FieldValue.serverTimestamp(),
        'lastSync': FieldValue.serverTimestamp(),
        'role': roleDefinida,
        'empresaId': finalEmpresaId,
        'plano': 'gratis', // <--- NOVA ETIQUETA INSERIDA AQUI
      });

      // 4. ATUALIZA STATUS DO CONVITE (se houver)
      if (conviteDoc != null) {
        await _firestore.collection('invites').doc(conviteDoc.id).update({
          'status': 'aceito',
          'usadoPor': user.uid,
          'dataAceite': FieldValue.serverTimestamp(),
        });
      }

      return null;
    } on FirebaseAuthException catch (e) {
      return _traduzirErro(e.code);
    } catch (e) {
      return "Erro ao cadastrar: $e";
    }
  }

  Future<String?> recuperarSenha(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      return _traduzirErro(e.code);
    } catch (e) {
      return "Erro: $e";
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
  }

  String _traduzirErro(String code) {
    switch (code) {
      case 'user-not-found':
        return 'E-mail não encontrado.';
      case 'wrong-password':
        return 'Senha incorreta.';
      case 'email-already-in-use':
        return 'Este e-mail já está cadastrado.';
      case 'invalid-email':
        return 'E-mail inválido.';
      case 'weak-password':
        return 'Senha muito fraca (mínimo 6 caracteres).';
      case 'network-request-failed':
        return 'Erro de conexão.';
      default:
        return 'Erro: $code';
    }
  }
}
