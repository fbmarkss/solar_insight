// Caminho: lib/services/session_manager.dart
// Descrição: Centraliza login/logout limpando todo o estado local.
//
// CORREÇÃO CRÍTICA (Web):
//   1. signOut() movido para ANTES da limpeza do Hive.
//      Isso faz o StreamBuilder do main.dart trocar para LoginScreen
//      e destruir os ValueListenableBuilder que escutam as boxes.
//   2. Delay de 300ms após signOut para dar tempo dessa troca acontecer.
//   3. _clearBoxSafe NÃO reabre box fechada (evita InvalidStateError do IndexedDB).
//   4. Cada limpeza de box em try/catch individual (uma falha não trava as outras).

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
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
  static const Duration _syncTimeout = Duration(seconds: 6);

  /// Tempo de espera após signOut para os ValueListenableBuilder
  /// da Web serem destruídos antes de limparmos as boxes.
  /// Sem isso, o IndexedDB Web dispara:
  ///   "InvalidStateError: database connection is closing"
  static const Duration _posSignOutDelay = Duration(milliseconds: 300);

  // ===========================================================================
  // LOGOUT COMPLETO
  // ===========================================================================
  static Future<void> logout(BuildContext context) async {
    // 1. Pausa o motor reativo
    SincronizacaoService.isPaused = true;

    // 2. Sync best-effort com timeout curto
    await _tentarSyncAntesDeSair();

    // 3. Reset dos providers (limpa estado de UI antes do signOut)
    try {
      if (context.mounted) {
        context.read<DashboardProvider>().reset();
        context.read<SubscriptionProvider>().reset();
      }
    } catch (e) {
      debugPrint('⚠️ [SessionManager] Erro ao resetar providers: $e');
    }

    // 4. signOut PRIMEIRO — antes de qualquer operação no Hive.
    //    Isso faz o StreamBuilder trocar para LoginScreen e destruir
    //    os ValueListenableBuilder que escutavam as boxes.
    try {
      await FirebaseAuth.instance.signOut();
      debugPrint('✅ [SessionManager] Firebase signOut concluído.');
    } catch (e) {
      debugPrint('❌ [SessionManager] Erro no signOut: $e');
    }

    // 5. Aguarda um pouco para o Navigator/StreamBuilder trocar de tela
    //    e os ValueListenableBuilder serem destruídos.
    await Future.delayed(_posSignOutDelay);

    // 6. Limpa fila de sync
    try {
      await SyncQueueService.clearAll();
    } catch (e) {
      debugPrint('⚠️ [SessionManager] Erro ao limpar fila: $e');
    }

    // 7. Limpa cada box individualmente (uma falha não trava as outras)
    await _clearBoxSafe<Usina>('usinas');
    await _clearBoxSafe<LancamentoMensal>('lancamentos');
    await _clearBoxSafe('sync_metadata');
    await _clearBoxSafe('auth_cache');

    // 8. Reset do motor reativo (cancela listeners de connectivity)
    try {
      await SincronizacaoService.resetMotorReativo();
    } catch (e) {
      debugPrint('⚠️ [SessionManager] Erro ao resetar motor: $e');
    }

    // 9. Garante que o motor não fica travado em paused
    SincronizacaoService.isPaused = false;

    debugPrint('✅ [SessionManager] Logout concluído com sucesso.');
  }

  // ===========================================================================
  // SYNC BEST-EFFORT COM TIMEOUT
  // ===========================================================================
  static Future<void> _tentarSyncAntesDeSair() async {
    try {
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
            '⏱️ [SessionManager] Sync estourou timeout. Prosseguindo.',
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
  static Future<void> prepararNovaSessao() async {
    try {
      await SyncQueueService.clearAll();
      await _clearBoxSafe<Usina>('usinas');
      await _clearBoxSafe<LancamentoMensal>('lancamentos');
      await _clearBoxSafe('sync_metadata');
      // ⚠️ NÃO limpa 'auth_cache' aqui, porque o SubscriptionProvider
      //    acabou de gravar plano/role do novo usuário nele.
      debugPrint('✅ [SessionManager] Estado local limpo para nova sessão.');
    } catch (e) {
      debugPrint('⚠️ [SessionManager] Erro ao preparar nova sessão: $e');
    }
  }

  // ===========================================================================
  // HELPER: limpar box com segurança (NÃO reabre box fechada)
  // ===========================================================================
  /// Limpa a box APENAS se ela estiver aberta.
  /// Se estiver fechada, NÃO tenta reabrir — isso evita o
  /// "InvalidStateError: database connection is closing" no IndexedDB da Web.
  static Future<void> _clearBoxSafe<T>(String name) async {
    try {
      if (!Hive.isBoxOpen(name)) {
        debugPrint(
          '⏭️ [SessionManager] Box $name já fechada. Pulando limpeza.',
        );
        return;
      }
      await Hive.box<T>(name).clear();
      debugPrint('🧹 [SessionManager] Box $name limpa.');
    } catch (e) {
      debugPrint('⚠️ [SessionManager] Falha ao limpar box $name: $e');
    }
  }
}
