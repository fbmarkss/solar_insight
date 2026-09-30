// Caminho: lib/services/auth_service.dart
// Descrição: Serviço de Autenticação com Warm-up de permissões e Cadastro Inteligente (Freemium).
//
// ALTERAÇÕES DESTA VERSÃO:
//   1. cadastrar() agora HERDA 'plano' e 'nomeEmpresa' do DONO da empresa
//      quando o novo usuário entra via convite. Sem isso, o colaborador
//      nascia como 'gratis' mesmo trabalhando numa empresa PRO.
//   2. Fallback seguro: se a leitura do dono falhar (rules/rede), usa
//      'gratis' — nunca quebra o cadastro.
//   3. logout() já aceitava contexto opcional — mantido.
//   4. Nenhuma outra função foi alterada.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart'; // BuildContext

import 'session_manager.dart'; // SessionManager (logout centralizado)

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  // ===========================================================================
  // LOGIN COM WARM-UP DE PERMISSÕES
  // ===========================================================================
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

  // ===========================================================================
  // CADASTRO INTELIGENTE (Freemium + Convites)
  // ===========================================================================
  /// Cria a conta. Se houver um convite pendente para o e-mail:
  ///   - Vincula o novo usuário à empresa do convite (empresaId)
  ///   - Herda o 'plano' do DONO (ex: 'pro')
  ///   - Herda o 'nomeEmpresa' do DONO
  ///   - Marca o convite como 'aceito'
  ///
  /// Se não houver convite: cria uma empresa própria com 'plano: gratis'.
  Future<String?> cadastrar(String nome, String email, String password) async {
    try {
      final emailLimpo = email.trim().toLowerCase();

      // 1. Cria o usuário no Auth
      UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(
            email: emailLimpo,
            password: password,
          );

      User? user = userCredential.user;
      if (user == null) return "Erro ao criar credenciais.";

      await user.updateDisplayName(nome);

      // 2. Busca convite pendente (protegido)
      String roleDefinida = 'admin';
      String? empresaIdVinculada;
      String? nomeEmpresaHerdado;
      String planoHerdado = 'gratis';
      DocumentSnapshot? conviteDoc;

      try {
        final conviteSnapshot = await _firestore
            .collection('invites')
            .where('email', isEqualTo: emailLimpo)
            .get();

        if (conviteSnapshot.docs.isNotEmpty) {
          // Filtra "pendente" localmente (evita índice composto)
          final pendentes = conviteSnapshot.docs
              .where((d) => d.data()['status'] == 'pendente')
              .toList();

          if (pendentes.isNotEmpty) {
            roleDefinida = 'user';
            conviteDoc = pendentes.first;
            final dadosConvite = conviteDoc.data() as Map<String, dynamic>;
            empresaIdVinculada =
                dadosConvite['empresaId'] ?? dadosConvite['invitedBy'];
            nomeEmpresaHerdado = dadosConvite['nomeEmpresa'];

            // ✅ NOVO: herda o plano do DONO da empresa
            if (empresaIdVinculada != null) {
              try {
                final donoDoc = await _firestore
                    .collection('users')
                    .doc(empresaIdVinculada)
                    .get();

                if (donoDoc.exists && donoDoc.data() != null) {
                  final dadosDono = donoDoc.data() as Map<String, dynamic>;
                  planoHerdado = dadosDono['plano'] ?? 'gratis';
                  // Se o convite não trouxe nomeEmpresa, herda do dono
                  nomeEmpresaHerdado ??= dadosDono['nomeEmpresa'];
                  debugPrint(
                    '🤝 [AuthService] Herdando do dono: plano=$planoHerdado | empresa=$nomeEmpresaHerdado',
                  );
                }
              } catch (e) {
                // Fallback seguro: mantém 'gratis' e segue
                debugPrint(
                  '⚠️ [AuthService] Falha ao herdar plano do dono: $e',
                );
              }
            }
          }
        }
      } catch (e) {
        debugPrint("Aviso: Falha ao checar convites: $e");
        // Prossegue como admin standalone para não travar cadastro
      }

      String finalEmpresaId = empresaIdVinculada ?? user.uid;

      // 3. Salva perfil com plano herdado (ou grátis se sem convite)
      final Map<String, dynamic> novoPerfil = {
        'uid': user.uid,
        'nome': nome,
        'email': emailLimpo,
        'createdAt': FieldValue.serverTimestamp(),
        'lastSync': FieldValue.serverTimestamp(),
        'role': roleDefinida,
        'empresaId': finalEmpresaId,
        'plano': planoHerdado, // ✅ herdado ou gratis
      };

      // Só adiciona nomeEmpresa se tiver valor (evita gravar null)
      if (nomeEmpresaHerdado != null && nomeEmpresaHerdado.isNotEmpty) {
        novoPerfil['nomeEmpresa'] = nomeEmpresaHerdado;
      }

      await _firestore.collection('users').doc(user.uid).set(novoPerfil);

      // 4. Marca convite como aceito
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

  // ===========================================================================
  // RECUPERAÇÃO DE SENHA
  // ===========================================================================
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

  // ===========================================================================
  // LOGOUT CENTRALIZADO
  // ===========================================================================
  /// Logout com duas modalidades:
  ///   • `AuthService().logout(context)` → fluxo COMPLETO via SessionManager.
  ///   • `AuthService().logout()`         → fallback simples (só signOut).
  Future<void> logout([BuildContext? context]) async {
    if (context != null && context.mounted) {
      await SessionManager.logout(context);
    } else {
      debugPrint(
        '⚠️ [AuthService] logout() sem contexto — apenas signOut() será executado.',
      );
      await _auth.signOut();
    }
  }

  // ===========================================================================
  // TRADUTOR DE ERROS
  // ===========================================================================
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
