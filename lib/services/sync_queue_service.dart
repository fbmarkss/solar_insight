// Caminho: lib/services/sync_queue_service.dart
// Descrição: Gerencia uma fila leve (Hive Box) de IDs que precisam ser enviados para a nuvem.
// Funciona como uma "Lista de Tarefas" para o SyncService.

import 'package:hive/hive.dart';

class SyncQueueService {
  static const String _boxName = 'sync_queue';

  /// Adiciona um item à fila de envio.
  /// [collection]: Nome da coleção no Firestore (ex: 'usinas', 'lancamentos').
  /// [docId]: ID do documento que foi alterado.
  static Future<void> enqueue(String collection, String docId) async {
    final box = await Hive.openBox(_boxName);

    // Cria uma chave composta única para evitar duplicatas na fila.
    // Se o item já estiver na fila, ele apenas atualiza o timestamp (o que é bom).
    final key = '${collection}_$docId';

    await box.put(key, {
      'collection': collection,
      'docId': docId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Retorna todos os itens pendentes para envio.
  static Future<List<Map<String, dynamic>>> getPendingItems() async {
    final box = await Hive.openBox(_boxName);

    // Converte os valores do Hive para uma lista de Mapas segura
    return box.values.map((e) {
      if (e is Map) {
        return Map<String, dynamic>.from(e);
      }
      return <String, dynamic>{};
    }).toList();
  }

  /// Remove um item específico da fila após o sucesso do envio.
  static Future<void> remove(String collection, String docId) async {
    final box = await Hive.openBox(_boxName);
    final key = '${collection}_$docId';
    await box.delete(key);
  }

  /// Limpa toda a fila (útil para logout ou reset).
  static Future<void> clearAll() async {
    final box = await Hive.openBox(_boxName);
    await box.clear();
  }
}
