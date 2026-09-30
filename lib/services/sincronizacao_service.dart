// Caminho: lib/services/sincronizacao_service.dart
// Status: 100% COMPLETO | Motor Reativo, Tradutor Blindado, Garbage Collector Agressivo.
//
// ALTERAÇÕES DESTA VERSÃO:
//   1. BLOQUEIO DE SYNC NO GRÁTIS: só PRO sincroniza (regra comercial).
//   2. JANELA DE MIGRAÇÃO PÓS-UPDATE: na primeira execução desta versão,
//      permite 1 sync completa para preservar dados legados.
//   3. MIGRAÇÃO GRÁTIS→PRO: força upload antes de download para não perder dados.
//   4. TODAS as proteções anteriores mantidas (Hive.isBoxOpen, resetMotorReativo,
//      dispararSyncEmergencial, guard de logout).

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../models/usina.dart';
import '../models/lancamento.dart';
import 'logger_service.dart';
import 'sync_queue_service.dart';

class SincronizacaoService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final LoggerService _logger = LoggerService();

  final Duration _prazoQuarentena = const Duration(days: 30);

  // ===========================================================================
  // CHAVES DE CONTROLE NO HIVE (sync_metadata)
  // ===========================================================================
  static const String _kMigracaoConcluida = 'migracao_v3_concluida';
  static const String _kMigracaoPosUpgrade = 'migracao_pos_upgrade_ativa';

  // ===========================================================================
  // ⚙️ MOTOR INVISÍVEL (REATIVIDADE E AUTO-START)
  // ===========================================================================
  static bool _isSyncing = false;
  static bool isPaused = false;
  static StreamSubscription? _conexaoSub;

  static void inicializarMotorReativo() {
    SyncQueueService.onQueueUpdated = () {
      _dispararSyncSilencioso();
    };

    _conexaoSub ??= Connectivity().onConnectivityChanged.listen((
      resultados,
    ) async {
      if (!resultados.contains(ConnectivityResult.none)) {
        bool temPendencia = await SyncQueueService.hasPendingItems();
        if (temPendencia) {
          debugPrint(
            '🌐 [MOTOR] Internet voltou e há fila! Disparando sync...',
          );
          _dispararSyncSilencioso();
        }
      }
    });

    _dispararSyncSilencioso();
  }

  /// Reset total do motor reativo. Chamado no logout.
  static Future<void> resetMotorReativo() async {
    await _conexaoSub?.cancel();
    _conexaoSub = null;
    _isSyncing = false;
    isPaused = false;
    SyncQueueService.onQueueUpdated = null;
    debugPrint('🔄 [MOTOR] Reset completo do motor reativo.');
  }

  /// Sync de emergência (fire-and-forget) para o ciclo de vida do app.
  static void dispararSyncEmergencial() {
    unawaited(_dispararSyncSilencioso());
  }

  static Future<void> _dispararSyncSilencioso() async {
    if (_isSyncing || isPaused) return;

    _isSyncing = true;
    try {
      if (!Hive.isBoxOpen('usinas') || !Hive.isBoxOpen('lancamentos')) {
        debugPrint('⏸️ [MOTOR] Boxes fechadas. Abortando sync silencioso.');
        return;
      }
      await SincronizacaoService().sincronizarTudo();
    } catch (e) {
      debugPrint('🔇 [MOTOR ERRO] Falha silenciosa: $e');
    } finally {
      _isSyncing = false;
    }
  }

  // ===========================================================================
  // 🛡️ HELPERS DE CONTROLE DE MIGRAÇÃO
  // ===========================================================================
  Future<Box> _getMetadataBox() async {
    if (!Hive.isBoxOpen('sync_metadata')) {
      await Hive.openBox('sync_metadata');
    }
    return Hive.box('sync_metadata');
  }

  /// Retorna `true` se a janela de migração pós-update ainda está ativa.
  /// A janela permite 1 sync completa (independente do plano) para
  /// preservar dados legados de usuários grátis.
  Future<bool> _isJanelaMigracaoAtiva() async {
    final box = await _getMetadataBox();
    return box.get(_kMigracaoConcluida, defaultValue: false) == false;
  }

  /// Fecha a janela de migração (chama depois do primeiro sync bem-sucedido).
  Future<void> _fecharJanelaMigracao() async {
    final box = await _getMetadataBox();
    await box.put(_kMigracaoConcluida, true);
    debugPrint('🔒 [MIGRAÇÃO] Janela de migração fechada.');
  }

  /// Retorna `true` se o usuário acabou de fazer upgrade grátis→PRO
  /// e ainda não subiu os dados locais.
  Future<bool> _isMigracaoPosUpgradeAtiva() async {
    final box = await _getMetadataBox();
    return box.get(_kMigracaoPosUpgrade, defaultValue: false) == true;
  }

  /// Marca a migração pós-upgrade como concluída (chama depois do upload).
  Future<void> _fecharMigracaoPosUpgrade() async {
    final box = await _getMetadataBox();
    await box.put(_kMigracaoPosUpgrade, false);
    debugPrint('🔒 [MIGRAÇÃO] Pós-upgrade concluída.');
  }

  /// Método público para o `SubscriptionProvider` sinalizar que houve
  /// uma mudança de plano grátis→PRO. Chama isso no momento do upgrade.
  static Future<void> sinalizarUpgradeParaPro() async {
    if (!Hive.isBoxOpen('sync_metadata')) {
      await Hive.openBox('sync_metadata');
    }
    await Hive.box('sync_metadata').put(_kMigracaoPosUpgrade, true);
    debugPrint('🚀 [MIGRAÇÃO] Upgrade grátis→PRO detectado. Flag ativada.');
  }

  // ===========================================================================
  // LÓGICA DE SINCRONIZAÇÃO PRINCIPAL
  // ===========================================================================
  /// Retorna o resumo da sincronização OU uma mensagem de bloqueio.
  /// O chamador deve exibir a mensagem apropriada ao usuário.
  Future<String> sincronizarTudo() async {
    if (isPaused) {
      debugPrint('--- ⏸️ [SYNC] Sincronização Pausada pelo Usuário. ---');
      return 'Erro: Sincronização pausada pelo usuário.';
    }

    if (!Hive.isBoxOpen('usinas') || !Hive.isBoxOpen('lancamentos')) {
      debugPrint('⏸️ [SYNC] Boxes fechadas. Abortando.');
      return 'Boxes fechadas.';
    }

    final user = _auth.currentUser;
    if (user == null) return 'Usuário offline.';

    final List<ConnectivityResult> connectivityResult = await (Connectivity()
        .checkConnectivity());
    if (connectivityResult.contains(ConnectivityResult.none)) {
      return 'Sem internet.';
    }

    // =========================================================================
    // 🛡️ GUARDA DE PLANO: sync só no PRO (com 2 exceções de migração)
    // =========================================================================
    final bool janelaMigracaoAtiva = await _isJanelaMigracaoAtiva();
    final bool migracaoPosUpgradeAtiva = await _isMigracaoPosUpgradeAtiva();

    // Verifica o plano diretamente no Firestore (não depende do Provider,
    // porque o Sync pode ser chamado de contextos sem Provider).
    bool empresaPro = false;
    try {
      final meuDoc = await _firestore.collection('users').doc(user.uid).get();
      final meuEmpresaId = meuDoc.data()?['empresaId'] ?? user.uid;
      final meuPlano = meuDoc.data()?['plano'] ?? 'gratis';

      if (meuEmpresaId == user.uid) {
        // Sou dono → meu plano é o da empresa
        empresaPro = meuPlano == 'pro';
      } else {
        // Sou colaborador → leio o plano do dono
        try {
          final donoDoc = await _firestore
              .collection('users')
              .doc(meuEmpresaId)
              .get();
          final planoDono = donoDoc.data()?['plano'] ?? 'gratis';
          empresaPro = planoDono == 'pro';
        } catch (e) {
          // Falha na leitura cross-user → fallback para meu próprio plano
          empresaPro = meuPlano == 'pro';
        }
      }
    } catch (e) {
      debugPrint('⚠️ [SYNC] Falha ao verificar plano: $e');
      // Em caso de falha, assume grátis para não vazar dados
      empresaPro = false;
    }

    // 🛡️ EXCEÇÃO 1: janela de migração pós-update ainda aberta
    if (!empresaPro && janelaMigracaoAtiva) {
      debugPrint(
        '🛡️ [SYNC] Janela de migração ativa. Permitindo 1 sync (grátis).',
      );
    }
    // 🛡️ EXCEÇÃO 2: migração grátis→PRO ativa
    else if (!empresaPro && !migracaoPosUpgradeAtiva) {
      debugPrint('🚫 [SYNC] Empresa grátis. Sync bloqueado.');
      return 'Sync é uma função PRO. Faça upgrade ou use Backup/Restore manual.';
    }

    try {
      debugPrint('--- 🔄 [SYNC] INICIANDO PROCESSO ---');

      await _firestore.collection('users').doc(user.uid).set({
        'lastSync': FieldValue.serverTimestamp(),
        'email': user.email,
      }, SetOptions(merge: true));

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      String empresaId = userDoc.data()?['empresaId'] ?? user.uid;
      bool isAdmin =
          userDoc.data()?['isAdmin'] == true || empresaId == user.uid;

      int usinasUp = 0;
      int usinasDown = 0;
      int lancamentosUp = 0;
      int lancamentosDown = 0;

      // =======================================================================
      // 🛡️ ORDEM DE OPERAÇÕES INTELIGENTE
      // Se a migração pós-upgrade está ativa, FORÇA upload ANTES de download.
      // Isso garante que dados locais subam sem serem sobrescritos.
      // =======================================================================
      if (migracaoPosUpgradeAtiva) {
        debugPrint(
          '🚀 [SYNC] MODO MIGRAÇÃO: upload forçado antes do download.',
        );
        usinasUp = await _enviarUsinasLocais(empresaId, user.uid);
        lancamentosUp = await _enviarLancamentosLocais(empresaId, user.uid);
        // Só depois de subir tudo, baixa o que houver na nuvem
        usinasDown = await _baixarUsinasRemotas(empresaId);
        lancamentosDown = await _baixarLancamentosRemotos(empresaId);
        // Fecha a flag de migração pós-upgrade
        await _fecharMigracaoPosUpgrade();
      } else {
        // Fluxo normal: upload + download em paralelo na ordem tradicional
        usinasUp = await _enviarUsinasLocais(empresaId, user.uid);
        usinasDown = await _baixarUsinasRemotas(empresaId);
        lancamentosUp = await _enviarLancamentosLocais(empresaId, user.uid);
        lancamentosDown = await _baixarLancamentosRemotos(empresaId);
      }

      int itensLimpos = 0;
      if (isAdmin) {
        itensLimpos = await _executarFaxinaInteligente(empresaId);
      }

      // Fecha a janela de migração pós-update (só na primeira sync bem-sucedida)
      if (janelaMigracaoAtiva) {
        await _fecharJanelaMigracao();
      }

      String resumo = 'Sincronizado.';
      int totalMovimento =
          usinasUp + usinasDown + lancamentosUp + lancamentosDown + itensLimpos;

      if (totalMovimento > 0) {
        resumo = 'Atividade: ';
        if (usinasUp > 0) resumo += '⬆$usinasUp Usinas ';
        if (usinasDown > 0) resumo += '⬇$usinasDown Usinas ';
        if (lancamentosUp > 0) resumo += '⬆$lancamentosUp Lanç. ';
        if (lancamentosDown > 0) resumo += '⬇$lancamentosDown Lanç. ';
        if (itensLimpos > 0) resumo += '🧹$itensLimpos Limpos';

        await _logger.logAction('SYNC_SUCCESS', resumo);
      } else {
        debugPrint('--- [SYNC] Nenhum dado novo. ---');
      }

      debugPrint('--- ✅ [SYNC] PROCESSO CONCLUÍDO ---');
      return resumo;
    } catch (e) {
      debugPrint('--- ❌ [SYNC ERROR] --- $e');
      await _logger.logAction('SYNC_ERROR', 'Falha: $e');
      return 'Erro ao sincronizar.';
    }
  }

  // ===========================================================================
  // USINAS (sem alterações na lógica interna)
  // ===========================================================================
  Future<int> _enviarUsinasLocais(String empresaId, String userId) async {
    int contador = 0;
    final box = Hive.box<Usina>('usinas');
    final queueItems = await SyncQueueService.getPendingItems();

    final queuedUsinas = queueItems
        .where((i) => i['collection'] == 'usinas')
        .map((i) => i['docId'] as String)
        .toSet();

    for (var usina in box.values) {
      if (usina.idRemoto == null || queuedUsinas.contains(usina.id)) {
        if (usina.idRemoto != null) {
          final docSnapshot = await _firestore
              .collection('usinas')
              .doc(usina.idRemoto)
              .get();

          if (!docSnapshot.exists) {
            await usina.delete();
            await SyncQueueService.remove('usinas', usina.id);
            continue;
          }
        }

        final docRef = usina.idRemoto == null
            ? _firestore.collection('usinas').doc()
            : _firestore.collection('usinas').doc(usina.idRemoto);

        var map = _usinaToMap(usina, empresaId);
        if (usina.idRemoto == null) map['criadoPor'] = userId;

        await docRef.set(map, SetOptions(merge: true));

        if (usina.idRemoto == null) {
          usina.idRemoto = docRef.id;
          usina.tenantId = empresaId;
          usina.criadoPor = userId;
        }

        if (!usina.isDeletado) usina.ultimaSincronizacao = DateTime.now();
        await usina.save();

        if (queuedUsinas.contains(usina.id)) {
          await SyncQueueService.remove('usinas', usina.id);
        }
        contador++;
      }
    }
    return contador;
  }

  Future<int> _baixarUsinasRemotas(String empresaId) async {
    int contador = 0;
    final box = Hive.box<Usina>('usinas');

    final snapshot = await _firestore
        .collection('usinas')
        .where('tenantId', isEqualTo: empresaId)
        .get();

    Set<String> idsNaNuvem = snapshot.docs.map((d) => d.id).toSet();

    for (var doc in snapshot.docs) {
      final dados = doc.data();
      DateTime dataNuvem = _converterParaDateTime(dados['ultimaAtualizacao']);

      final usinaLocal = box.values.firstWhere(
        (u) => u.idRemoto == doc.id,
        orElse: () =>
            Usina(id: '', nome: '', concessionaria: '', tipo: '', ativa: false),
      );

      if (usinaLocal.id.isEmpty) {
        if (dados['isDeletado'] != true) {
          await box.add(_mapToUsina(dados, doc.id));
          contador++;
        }
      } else if (usinaLocal.ultimaSincronizacao == null ||
          dataNuvem.isAfter(usinaLocal.ultimaSincronizacao!)) {
        _atualizarUsinaComMap(usinaLocal, dados);
        if (!usinaLocal.isDeletado) {
          usinaLocal.ultimaSincronizacao = DateTime.now();
        }
        await usinaLocal.save();
        contador++;
      }
    }

    final usinasParaApagar = box.values
        .where((u) => u.idRemoto != null && !idsNaNuvem.contains(u.idRemoto))
        .toList();
    for (var u in usinasParaApagar) {
      await u.delete();
      contador++;
    }

    return contador;
  }

  // ===========================================================================
  // LANÇAMENTOS
  // ===========================================================================
  Future<int> _enviarLancamentosLocais(String empresaId, String userId) async {
    int contador = 0;
    final box = Hive.box<LancamentoMensal>('lancamentos');
    final queueItems = await SyncQueueService.getPendingItems();
    final queuedLancamentos = queueItems
        .where((i) => i['collection'] == 'lancamentos')
        .map((i) => i['docId'] as String)
        .toSet();

    for (var l in box.values) {
      if (l.idRemoto == null || queuedLancamentos.contains(l.id)) {
        if (l.idRemoto != null) {
          final docSnapshot = await _firestore
              .collection('lancamentos')
              .doc(l.idRemoto)
              .get();

          if (!docSnapshot.exists) {
            await l.delete();
            await SyncQueueService.remove('lancamentos', l.id);
            continue;
          }
        }

        final docRef = l.idRemoto == null
            ? _firestore.collection('lancamentos').doc()
            : _firestore.collection('lancamentos').doc(l.idRemoto);

        var map = _lancamentoToMap(l, empresaId);
        if (l.idRemoto == null) map['criadoPor'] = userId;

        await docRef.set(map, SetOptions(merge: true));

        if (l.idRemoto == null) {
          l.idRemoto = docRef.id;
          l.tenantId = empresaId;
          l.criadoPor = userId;
        }

        if (!l.isDeletado) l.ultimaSincronizacao = DateTime.now();
        await l.save();

        if (queuedLancamentos.contains(l.id)) {
          await SyncQueueService.remove('lancamentos', l.id);
        }
        contador++;
      }
    }
    return contador;
  }

  Future<int> _baixarLancamentosRemotos(String empresaId) async {
    int contador = 0;
    final box = Hive.box<LancamentoMensal>('lancamentos');
    final snapshot = await _firestore
        .collection('lancamentos')
        .where('tenantId', isEqualTo: empresaId)
        .get();

    Set<String> idsNaNuvem = snapshot.docs.map((d) => d.id).toSet();

    for (var doc in snapshot.docs) {
      final dados = doc.data();
      DateTime dataNuvem = _converterParaDateTime(dados['ultimaAtualizacao']);

      final local = box.values.firstWhere(
        (l) => l.idRemoto == doc.id,
        orElse: () => LancamentoMensal(
          usinaId: '',
          dataReferencia: DateTime.now(),
          geracaoTotalKwh: 0,
          energiaInjetadaKwh: 0,
          energiaConsumidaRedeKwh: 0,
          tarifaKwh: 0,
          valorFaturaR: 0,
        ),
      );

      if (local.usinaId.isEmpty) {
        if (dados['isDeletado'] != true) {
          await box.add(_mapToLancamento(dados, doc.id));
          contador++;
        }
      } else if (local.ultimaModificacao == null ||
          dataNuvem.isAfter(local.ultimaModificacao!)) {
        _atualizarLancamentoComMap(local, dados);
        if (!local.isDeletado) local.ultimaSincronizacao = DateTime.now();
        await local.save();
        contador++;
      }
    }

    final lancsParaApagar = box.values
        .where((l) => l.idRemoto != null && !idsNaNuvem.contains(l.idRemoto))
        .toList();
    for (var l in lancsParaApagar) {
      await l.delete();
      contador++;
    }

    return contador;
  }

  // ===========================================================================
  // 🧠 FAXINA INTELIGENTE
  // ===========================================================================
  Future<int> _executarFaxinaInteligente(String empresaId) async {
    int totalRemovido = 0;
    final usersSnapshot = await _firestore
        .collection('users')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    DateTime dataSyncMaisAntiga = DateTime.now();

    if (usersSnapshot.docs.length <= 1) {
      dataSyncMaisAntiga = DateTime.now().add(const Duration(days: 1));
    } else {
      for (var doc in usersSnapshot.docs) {
        final dados = doc.data();
        if (dados['lastSync'] != null) {
          DateTime lastSync = _converterParaDateTime(dados['lastSync']);
          if (lastSync.isBefore(dataSyncMaisAntiga)) {
            dataSyncMaisAntiga = lastSync;
          }
        } else {
          dataSyncMaisAntiga = DateTime(2000, 1, 1);
        }
      }
    }

    DateTime dataLimiteAbsoluta = DateTime.now().subtract(_prazoQuarentena);

    final boxUsinas = Hive.box<Usina>('usinas');
    final usinasLixo = boxUsinas.values
        .where((u) => u.isDeletado && u.idRemoto != null)
        .toList();

    for (var u in usinasLixo) {
      DateTime dataDelecao = u.ultimaSincronizacao ?? DateTime.now();
      if (dataSyncMaisAntiga.isAfter(dataDelecao) ||
          dataDelecao.isBefore(dataLimiteAbsoluta)) {
        await _firestore.collection('usinas').doc(u.idRemoto).delete();
        await u.delete();
        await SyncQueueService.remove('usinas', u.id);
        totalRemovido++;
      }
    }

    final boxLanc = Hive.box<LancamentoMensal>('lancamentos');
    final lancsLixo = boxLanc.values
        .where((l) => l.isDeletado && l.idRemoto != null)
        .toList();

    for (var l in lancsLixo) {
      DateTime dataDelecao = l.ultimaModificacao ?? DateTime.now();
      if (dataSyncMaisAntiga.isAfter(dataDelecao) ||
          dataDelecao.isBefore(dataLimiteAbsoluta)) {
        await _firestore.collection('lancamentos').doc(l.idRemoto).delete();
        await l.delete();
        await SyncQueueService.remove('lancamentos', l.id);
        totalRemovido++;
      }
    }
    return totalRemovido;
  }

  // ===========================================================================
  // HELPERS DE CONVERSÃO (idênticos à versão anterior)
  // ===========================================================================
  DateTime _converterParaDateTime(dynamic valor) {
    if (valor == null) return DateTime.now();
    if (valor is Timestamp) return valor.toDate();
    if (valor is int) return DateTime.fromMillisecondsSinceEpoch(valor);
    if (valor is String) return DateTime.tryParse(valor) ?? DateTime.now();
    if (valor is DateTime) return valor;
    return DateTime.now();
  }

  Map<String, dynamic> _usinaToMap(Usina u, String empresaId) {
    return {
      'nome': u.nome,
      'uc': u.id,
      'concessionaria': u.concessionaria,
      'tipo': u.tipo,
      'ativa': u.ativa,
      'tenantId': empresaId,
      'isDeletado': u.isDeletado,
      'ultimaAtualizacao': FieldValue.serverTimestamp(),
      'inversores': u.inversores
          .map(
            (i) => {
              'marca': i.marca,
              'potenciaKw': i.potenciaKw,
              'quantidade': i.quantidade,
            },
          )
          .toList(),
      'paineis': u.paineis
          .map(
            (p) => {
              'marca': p.marca,
              'potenciaWatts': p.potenciaWatts,
              'quantidade': p.quantidade,
            },
          )
          .toList(),
      'investimentos': u.investimentos
          .map(
            (inv) => {
              'data': inv.data.millisecondsSinceEpoch,
              'descricao': inv.descricao,
              'valor': inv.valor,
            },
          )
          .toList(),
      'beneficiarias': u.beneficiarias
          .map(
            (b) => {
              'nome': b.nome,
              'idUsinaFilha': b.idUsinaFilha,
              'percentual': b.percentual,
              'dataInicio': b.dataInicio.millisecondsSinceEpoch,
              'dataFim': b.dataFim?.millisecondsSinceEpoch,
            },
          )
          .toList(),
    };
  }

  Usina _mapToUsina(Map<String, dynamic> map, String idRemoto) {
    return Usina(
      id: map['uc'] ?? '',
      nome: map['nome'] ?? '',
      concessionaria: map['concessionaria'] ?? '',
      tipo: map['tipo'] ?? '',
      ativa: map['ativa'] ?? true,
      idRemoto: idRemoto,
      tenantId: map['tenantId'],
      criadoPor: map['criadoPor'],
      isDeletado: map['isDeletado'] ?? false,
      ultimaSincronizacao: _converterParaDateTime(map['ultimaAtualizacao']),
      inversores: (map['inversores'] as List? ?? [])
          .map(
            (i) => InversorItem(
              marca: i['marca'],
              potenciaKw: (i['potenciaKw'] as num).toDouble(),
              quantidade: i['quantidade'],
            ),
          )
          .toList(),
      paineis: (map['paineis'] as List? ?? [])
          .map(
            (p) => PainelItem(
              marca: p['marca'],
              potenciaWatts: (p['potenciaWatts'] as num).toDouble(),
              quantidade: p['quantidade'],
            ),
          )
          .toList(),
      investimentos: (map['investimentos'] as List? ?? [])
          .map(
            (inv) => InvestimentoItem(
              data: _converterParaDateTime(inv['data']),
              descricao: inv['descricao'],
              valor: (inv['valor'] as num).toDouble(),
            ),
          )
          .toList(),
      beneficiarias: (map['beneficiarias'] as List? ?? [])
          .map(
            (b) => BeneficiariaItem(
              nome: b['nome'] ?? '',
              idUsinaFilha: b['idUsinaFilha'] ?? '',
              percentual: (b['percentual'] as num).toDouble(),
              dataInicio: b['dataInicio'] != null
                  ? _converterParaDateTime(b['dataInicio'])
                  : DateTime(2000, 1, 1),
              dataFim: b['dataFim'] != null
                  ? _converterParaDateTime(b['dataFim'])
                  : null,
            ),
          )
          .toList(),
    );
  }

  void _atualizarUsinaComMap(Usina u, Map<String, dynamic> m) {
    u.nome = m['nome'] ?? u.nome;
    u.concessionaria = m['concessionaria'] ?? u.concessionaria;
    u.ativa = m['ativa'] ?? u.ativa;
    u.isDeletado = m['isDeletado'] ?? false;
    u.tipo = m['tipo'] ?? u.tipo;

    final usinaAtualizada = _mapToUsina(m, u.idRemoto!);
    u.inversores = usinaAtualizada.inversores;
    u.paineis = usinaAtualizada.paineis;
    u.investimentos = usinaAtualizada.investimentos;
    u.beneficiarias = usinaAtualizada.beneficiarias;
  }

  Map<String, dynamic> _lancamentoToMap(LancamentoMensal l, String empresaId) {
    return {
      'id': l.id,
      'usinaId': l.usinaId,
      'dataReferencia': l.dataReferencia.millisecondsSinceEpoch,
      'geracaoTotalKwh': l.geracaoTotalKwh,
      'energiaInjetadaKwh': l.energiaInjetadaKwh,
      'energiaConsumidaRedeKwh': l.energiaConsumidaRedeKwh,
      'tarifaKwh': l.tarifaKwh,
      'valorFaturaR': l.valorFaturaR,
      'observacao': l.observacao,
      'leituraInversor': l.leituraInversor,
      'custoDemandaR': l.custoDemandaR,
      'tenantId': empresaId,
      'isDeletado': l.isDeletado,
      'fonteOrigem': l.fonteOrigem,
      'editadoPor': l.editadoPor,
      'ultimaAtualizacao': FieldValue.serverTimestamp(),
      'saldoInformadoNaFatura': l.saldoInformadoNaFatura,
      'creditosRecebidosDeTerceiros': l.creditosRecebidosDeTerceiros,
      'saldoAnteriorFatura': l.saldoAnteriorFatura,
      'grupoTarifario': l.grupoTarifario,
      'modalidadeTarifaria': l.modalidadeTarifaria,
      'consumoPonta': l.consumoPonta,
      'consumoForaPonta': l.consumoForaPonta,
      'consumoReservado': l.consumoReservado,
      'injetadaPonta': l.injetadaPonta,
      'injetadaForaPonta': l.injetadaForaPonta,
      'injetadaReservada': l.injetadaReservada,
      'tarifaTeUnica': l.tarifaTeUnica,
      'tarifaTusdUnica': l.tarifaTusdUnica,
      'tarifaTePonta': l.tarifaTePonta,
      'tarifaTusdPonta': l.tarifaTusdPonta,
      'tarifaTeForaPonta': l.tarifaTeForaPonta,
      'tarifaTusdForaPonta': l.tarifaTusdForaPonta,
      'custoIluminacaoPublica': l.custoIluminacaoPublica,
      'multaReativo': l.multaReativo,
    };
  }

  LancamentoMensal _mapToLancamento(Map<String, dynamic> map, String idRemoto) {
    return LancamentoMensal(
      id: map['id'],
      usinaId: map['usinaId'] ?? '',
      dataReferencia: _converterParaDateTime(map['dataReferencia']),
      geracaoTotalKwh: (map['geracaoTotalKwh'] as num?)?.toDouble() ?? 0.0,
      energiaInjetadaKwh:
          (map['energiaInjetadaKwh'] as num?)?.toDouble() ?? 0.0,
      energiaConsumidaRedeKwh:
          (map['energiaConsumidaRedeKwh'] as num?)?.toDouble() ?? 0.0,
      tarifaKwh: (map['tarifaKwh'] as num?)?.toDouble() ?? 0.0,
      valorFaturaR: (map['valorFaturaR'] as num?)?.toDouble() ?? 0.0,
      observacao: map['observacao'],
      leituraInversor: (map['leituraInversor'] as num?)?.toDouble(),
      custoDemandaR: (map['custoDemandaR'] as num?)?.toDouble() ?? 0.0,
      idRemoto: idRemoto,
      tenantId: map['tenantId'],
      ultimaModificacao: _converterParaDateTime(map['ultimaAtualizacao']),
      isDeletado: map['isDeletado'] ?? false,
      fonteOrigem: map['fonteOrigem'] ?? 'MANUAL',
      editadoPor: map['editadoPor'],
      criadoPor: map['criadoPor'],
      saldoInformadoNaFatura: (map['saldoInformadoNaFatura'] as num?)
          ?.toDouble(),
      creditosRecebidosDeTerceiros:
          (map['creditosRecebidosDeTerceiros'] as num?)?.toDouble(),
      saldoAnteriorFatura: (map['saldoAnteriorFatura'] as num?)?.toDouble(),
      grupoTarifario: map['grupoTarifario'],
      modalidadeTarifaria: map['modalidadeTarifaria'],
      consumoPonta: (map['consumoPonta'] as num?)?.toDouble(),
      consumoForaPonta: (map['consumoForaPonta'] as num?)?.toDouble(),
      consumoReservado: (map['consumoReservado'] as num?)?.toDouble(),
      injetadaPonta: (map['injetadaPonta'] as num?)?.toDouble(),
      injetadaForaPonta: (map['injetadaForaPonta'] as num?)?.toDouble(),
      injetadaReservada: (map['injetadaReservada'] as num?)?.toDouble(),
      tarifaTeUnica: (map['tarifaTeUnica'] as num?)?.toDouble(),
      tarifaTusdUnica: (map['tarifaTusdUnica'] as num?)?.toDouble(),
      tarifaTePonta: (map['tarifaTePonta'] as num?)?.toDouble(),
      tarifaTusdPonta: (map['tarifaTusdPonta'] as num?)?.toDouble(),
      tarifaTeForaPonta: (map['tarifaTeForaPonta'] as num?)?.toDouble(),
      tarifaTusdForaPonta: (map['tarifaTusdForaPonta'] as num?)?.toDouble(),
      custoIluminacaoPublica: (map['custoIluminacaoPublica'] as num?)
          ?.toDouble(),
      multaReativo: (map['multaReativo'] as num?)?.toDouble(),
    );
  }

  void _atualizarLancamentoComMap(LancamentoMensal l, Map<String, dynamic> m) {
    final lNuvem = _mapToLancamento(m, l.idRemoto!);

    l.dataReferencia = lNuvem.dataReferencia;
    l.geracaoTotalKwh = lNuvem.geracaoTotalKwh;
    l.energiaInjetadaKwh = lNuvem.energiaInjetadaKwh;
    l.energiaConsumidaRedeKwh = lNuvem.energiaConsumidaRedeKwh;
    l.tarifaKwh = lNuvem.tarifaKwh;
    l.valorFaturaR = lNuvem.valorFaturaR;
    l.custoDemandaR = lNuvem.custoDemandaR;
    l.leituraInversor = lNuvem.leituraInversor;
    l.observacao = lNuvem.observacao;
    l.isDeletado = lNuvem.isDeletado;
    l.ultimaModificacao = lNuvem.ultimaModificacao;
    l.saldoInformadoNaFatura = lNuvem.saldoInformadoNaFatura;
    l.creditosRecebidosDeTerceiros = lNuvem.creditosRecebidosDeTerceiros;
    l.saldoAnteriorFatura = lNuvem.saldoAnteriorFatura;
    l.grupoTarifario = lNuvem.grupoTarifario;
    l.modalidadeTarifaria = lNuvem.modalidadeTarifaria;
    l.consumoPonta = lNuvem.consumoPonta;
    l.consumoForaPonta = lNuvem.consumoForaPonta;
    l.consumoReservado = lNuvem.consumoReservado;
    l.injetadaPonta = lNuvem.injetadaPonta;
    l.injetadaForaPonta = lNuvem.injetadaForaPonta;
    l.injetadaReservada = lNuvem.injetadaReservada;
    l.tarifaTeUnica = lNuvem.tarifaTeUnica;
    l.tarifaTusdUnica = lNuvem.tarifaTusdUnica;
    l.tarifaTePonta = lNuvem.tarifaTePonta;
    l.tarifaTusdPonta = lNuvem.tarifaTusdPonta;
    l.tarifaTeForaPonta = lNuvem.tarifaTeForaPonta;
    l.tarifaTusdForaPonta = lNuvem.tarifaTusdForaPonta;
    l.custoIluminacaoPublica = lNuvem.custoIluminacaoPublica;
    l.multaReativo = lNuvem.multaReativo;
  }
}
