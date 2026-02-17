// Caminho: lib/services/sincronizacao_service.dart
// Status: 100% COMPLETO | Motor Reativo Background + Smart Garbage Collector.

import 'dart:async'; // Necessário para o StreamSubscription do Motor
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
  // ⚙️ MOTOR INVISÍVEL (REATIVIDADE E AUTO-START)
  // ===========================================================================
  static bool _isSyncing = false;
  static bool isPaused = false; // <-- CHAVE GERAL DE PAUSA ADICIONADA
  static StreamSubscription? _conexaoSub;

  /// Inicia o "Despertador" e os ouvintes de Fila e Conexão.
  /// Chamado uma vez ao abrir o App.
  static void inicializarMotorReativo() {
    // 1. Ouve a Fila: Se alguém salvar algo localmente, tenta sincronizar na hora.
    SyncQueueService.onQueueUpdated = () {
      _dispararSyncSilencioso();
    };

    // 2. Ouve a Internet: Se o celular/PC reconectar, verifica se tem fila parada.
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

    // 3. Auto-Start: Faz uma verificação de segurança assim que o app liga.
    _dispararSyncSilencioso();
  }

  /// Executa a sincronização em segundo plano com trava para não atropelar processos.
  static Future<void> _dispararSyncSilencioso() async {
    if (_isSyncing || isPaused) {
      return; // <-- BLOQUEIO ADICIONADO SE ESTIVER PAUSADO
    }

    _isSyncing = true;
    try {
      await SincronizacaoService().sincronizarTudo();
    } catch (e) {
      debugPrint('🔇 [MOTOR ERRO] Falha silenciosa: $e');
    } finally {
      _isSyncing = false; // Libera a trava quando terminar
    }
  }

  // ===========================================================================
  // LÓGICA DE SINCRONIZAÇÃO PRINCIPAL
  // ===========================================================================

  Future<String> sincronizarTudo() async {
    // <-- BLOQUEIO MANUAL ADICIONADO AQUI TAMBÉM
    if (isPaused) {
      debugPrint('--- ⏸️ [SYNC] Sincronização Pausada pelo Usuário. ---');
      return 'Erro: Sincronização pausada pelo usuário.';
    }

    final user = _auth.currentUser;
    if (user == null) return 'Usuário offline.';

    final List<ConnectivityResult> connectivityResult = await (Connectivity()
        .checkConnectivity());
    if (connectivityResult.contains(ConnectivityResult.none)) {
      return 'Sem internet.';
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

      int usinasUp = await _enviarUsinasLocais(empresaId, user.uid);
      int usinasDown = await _baixarUsinasRemotas(empresaId);
      int lancamentosUp = await _enviarLancamentosLocais(empresaId, user.uid);
      int lancamentosDown = await _baixarLancamentosRemotos(empresaId);

      int itensLimpos = 0;
      if (isAdmin) {
        itensLimpos = await _executarFaxinaInteligente(empresaId);
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
  // USINAS (COM PROTEÇÃO ZOMBIE DATA)
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
            final ultimaMod = usina.ultimaSincronizacao ?? DateTime.now();
            final diasSemSync = DateTime.now().difference(ultimaMod).inDays;

            if (diasSemSync > 30) {
              debugPrint(
                '🧟 [ZOMBIE KILL] Usina ${usina.nome} deletada localmente (Lixo antigo).',
              );
              await usina.delete();
              await SyncQueueService.remove('usinas', usina.id);
              continue;
            }
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
      debugPrint(
        '🗑️ [HARD DELETE LOCAL] Usina ${u.nome} não existe mais na nuvem.',
      );
      await u.delete();
      contador++;
    }

    return contador;
  }

  // ===========================================================================
  // LANÇAMENTOS (COM PROTEÇÃO ZOMBIE DATA)
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
            final ultimaMod = l.ultimaModificacao ?? DateTime.now();
            if (DateTime.now().difference(ultimaMod).inDays > 30) {
              debugPrint('🧟 [ZOMBIE KILL] Lançamento deletado localmente.');
              await l.delete();
              await SyncQueueService.remove('lancamentos', l.id);
              continue;
            }
          }
        }

        final docRef = l.idRemoto == null
            ? _firestore.collection('lancamentos').doc()
            : _firestore.collection('lancamentos').doc(l.idRemoto);

        var map = l.toMap();
        map['tenantId'] = empresaId;
        map['ultimaAtualizacao'] = FieldValue.serverTimestamp();
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
          await box.add(LancamentoMensal.fromMap(dados)..idRemoto = doc.id);
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
  // 🧠 FAXINA INTELIGENTE (Smart Garbage Collector)
  // ===========================================================================

  Future<int> _executarFaxinaInteligente(String empresaId) async {
    debugPrint('🧹 [FAXINA] Iniciando análise inteligente...');
    int totalRemovido = 0;

    final usersSnapshot = await _firestore
        .collection('users')
        .where('empresaId', isEqualTo: empresaId)
        .get();

    DateTime dataSyncMaisAntiga = DateTime.now();

    if (usersSnapshot.docs.length <= 1) {
      debugPrint('🧹 [FAXINA] Único usuário. Modo limpeza total ativado.');
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

    debugPrint(
      '🧹 [FAXINA] Elo mais fraco sincronizou em: $dataSyncMaisAntiga',
    );

    final boxUsinas = Hive.box<Usina>('usinas');
    final usinasLixo = boxUsinas.values
        .where((u) => u.isDeletado && u.idRemoto != null)
        .toList();

    for (var u in usinasLixo) {
      DateTime dataDelecao = u.ultimaSincronizacao ?? DateTime.now();
      bool podeMatar =
          dataSyncMaisAntiga.isAfter(dataDelecao) ||
          dataDelecao.isBefore(dataLimiteAbsoluta);

      if (podeMatar) {
        await _firestore.collection('usinas').doc(u.idRemoto).delete();
        await u.delete();
        await SyncQueueService.remove('usinas', u.id);
        totalRemovido++;
        debugPrint('🧹 [FAXINA] Usina ${u.nome} removida permanentemente.');
      }
    }

    final boxLanc = Hive.box<LancamentoMensal>('lancamentos');
    final lancsLixo = boxLanc.values
        .where((l) => l.isDeletado && l.idRemoto != null)
        .toList();

    for (var l in lancsLixo) {
      DateTime dataDelecao = l.ultimaModificacao ?? DateTime.now();
      bool podeMatar =
          dataSyncMaisAntiga.isAfter(dataDelecao) ||
          dataDelecao.isBefore(dataLimiteAbsoluta);

      if (podeMatar) {
        await _firestore.collection('lancamentos').doc(l.idRemoto).delete();
        await l.delete();
        await SyncQueueService.remove('lancamentos', l.id);
        totalRemovido++;
      }
    }

    return totalRemovido;
  }

  // ===========================================================================
  // HELPERS DE CONVERSÃO
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
    );
  }

  void _atualizarUsinaComMap(Usina u, Map<String, dynamic> m) {
    u.nome = m['nome'] ?? u.nome;
    u.concessionaria = m['concessionaria'] ?? u.concessionaria;
    u.ativa = m['ativa'] ?? u.ativa;
    u.isDeletado = m['isDeletado'] ?? false;
  }

  void _atualizarLancamentoComMap(LancamentoMensal l, Map<String, dynamic> m) {
    if (m['dataReferencia'] != null) {
      l.dataReferencia = _converterParaDateTime(m['dataReferencia']);
    }
    l.geracaoTotalKwh = (m['geracaoTotalKwh'] as num?)?.toDouble() ?? 0.0;
    l.valorFaturaR = (m['valorFaturaR'] as num?)?.toDouble() ?? 0.0;
    l.energiaInjetadaKwh = (m['energiaInjetadaKwh'] as num?)?.toDouble() ?? 0.0;
    l.energiaConsumidaRedeKwh =
        (m['energiaConsumidaRedeKwh'] as num?)?.toDouble() ?? 0.0;
    l.tarifaKwh = (m['tarifaKwh'] as num?)?.toDouble() ?? 0.0;
    l.custoDemandaR = (m['custoDemandaR'] as num?)?.toDouble() ?? 0.0;
    l.leituraInversor = (m['leituraInversor'] as num?)?.toDouble();
    l.observacao = m['observacao'];
    l.isDeletado = m['isDeletado'] ?? false;
    l.ultimaModificacao = _converterParaDateTime(m['ultimaAtualizacao']);
  }
}
