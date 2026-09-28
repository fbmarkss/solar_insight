// Caminho: lib/services/session_manager.dart
// Descrição: Centraliza login/logout limpando todo o estado local (Hive, Providers,
//            serviços estáticos) para evitar contaminação entre usuários na Web/Mobile/Windows.
//            Também tenta sincronizar antes de deslogar (best-effort com timeout).

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
//import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import '../models/usina.dart';
import '../models/lancamento.dart';
import 'dashboard_provider.dart';
import 'subscription_provider.dart';
import 'sincronizacao_service.dart';
import 'sync_queue_service.dart';

class SessionManager {
  /// Timeout máximo para tentar sincronizar antes do logout.
  /// Se estourar, o logout prossegue mesmo assim.
  static const Duration _syncTimeout = Duration(seconds: 6);

  // ===========================================================================
  // LOGOUT COMPLETO (com sync best-effort antes)
  // ===========================================================================
  /// Faz logout completo em QUALQUER plataforma (Web/Mobile/Windows).
  ///
  /// Ordem de execução:
  ///   1. Pausa o motor reativo (evita concorrência)
  ///   2. Sync best-effort com timeout curto
  ///   3. Limpa fila de sync
  ///   4. Limpa boxes locais (usinas, lancamentos, sync_metadata, auth_cache)
  ///   5. Reseta providers
  ///   6. Reset do motor reativo (cancela listeners de connectivity)
  ///   7. signOut() no Firebase
  static Future<void> logout(BuildContext context) async {
    try {
      // 1. Pausa o motor para não competir com nosso sync manual
      SincronizacaoService.isPaused = true;

      // 2. SYNC BEST-EFFORT: tenta enviar pendências, mas não bloqueia mais que 6s
      await _tentarSyncAntesDeSair();

      // 3. Limpa a fila de sincronização
      await SyncQueueService.clearAll();

      // 4. Limpa TODAS as boxes de dados do usuário
      await _clearBox<Usina>('usinas');
      await _clearBox<LancamentoMensal>('lancamentos');
      await _clearBox('sync_metadata');
      // ⚠️ auth_cache também é limpo para não deixar plano/role do usuário anterior
      await _clearBox('auth_cache');

      // 5. Reseta providers (evita dashboards antigos na memória)
      if (context.mounted) {
        context.read<DashboardProvider>().reset();
        context.read<SubscriptionProvider>().reset();
      }

      // 6. Reset completo do motor reativo (cancela listeners de connectivity)
      await SincronizacaoService.resetMotorReativo();

      // 7. Desloga do Firebase (dispara authStateChanges -> LoginScreen)
      await FirebaseAuth.instance.signOut();

      debugPrint('✅ [SessionManager] Logout concluído com sucesso.');
    } catch (e) {
      debugPrint('❌ [SessionManager] Erro no logout: $e');
      // Mesmo com erro, garante o logout do Firebase
      try {
        await FirebaseAuth.instance.signOut();
      } catch (e2) {
        debugPrint('❌ [SessionManager] Falha crítica no signOut: $e2');
      }
    } finally {
      SincronizacaoService.isPaused = false;
    }
  }

  // ===========================================================================
  // SYNC BEST-EFFORT COM TIMEOUT
  // ===========================================================================
  static Future<void> _tentarSyncAntesDeSair() async {
    try {
      // Se não há fila pendente, nem tenta (economiza 6s)
      final temPendencia = await SyncQueueService.hasPendingItems();
      if (!temPendencia) {
        debugPrint(
          'ℹ️ [SessionManager] Sem pendências. Pulando sync pré-logout.',
        );
        return;
      }

      debugPrint('🔄 [SessionManager] Sincronizando antes de deslogar...');

      final resultado = await SincronizacaoService().sincronizarTudo().timeout(
        _syncTimeout,
        onTimeout: () {
          debugPrint(
            '⏱️ [SessionManager] Sync estourou o timeout ($_syncTimeout). Prosseguindo.',
          );
          return 'Timeout';
        },
      );

      debugPrint('✅ [SessionManager] Sync pré-logout: $resultado');
    } catch (e) {
      debugPrint(
        '⚠️ [SessionManager] Sync pré-logout falhou (segue logout): $e',
      );
    }
  }

  // ===========================================================================
  // PREPARAR NOVA SESSÃO (após login/cadastro)
  // ===========================================================================
  /// Chamado APÓS login/cadastro bem-sucedido.
  /// Garante que nenhum dado residual do usuário anterior persista.
  static Future<void> prepararNovaSessao() async {
    try {
      await SyncQueueService.clearAll();
      await _clearBox<Usina>('usinas');
      await _clearBox<LancamentoMensal>('lancamentos');
      await _clearBox('sync_metadata');
      // ⚠️ NÃO limpa 'auth_cache' aqui, porque o SubscriptionProvider
      //    acabou de gravar plano/role do novo usuário nele.
      debugPrint('✅ [SessionManager] Estado local limpo para nova sessão.');
    } catch (e) {
      debugPrint('⚠️ [SessionManager] Erro ao preparar nova sessão: $e');
    }
  }

  // ===========================================================================
  // HELPER: limpar box com segurança
  // ===========================================================================
  static Future<void> _clearBox<T>(String name) async {
    try {
      if (!Hive.isBoxOpen(name)) {
        await Hive.openBox<T>(name);
      }
      await Hive.box<T>(name).clear();
    } catch (e) {
      debugPrint('⚠️ [SessionManager] Falha ao limpar box $name: $e');
    }
  }
}
