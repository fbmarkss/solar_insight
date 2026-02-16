// Caminho: lib/interfaces/syncable_model.dart
// Descrição: Interface que padroniza os modelos (Usina/Lançamento) para a sincronização.
// Define que todo objeto sincronizável deve ter ID, Data de Modificação, Flag de Deleção e conversão para Map.

abstract class SyncableModel {
  // O ID único do objeto (UUID gerado localmente ou pelo Firestore)
  String get id;

  // Controle de Conflito: O SyncService usará esta data para decidir
  // se o dado da nuvem é mais recente que o local (Last Write Wins).
  DateTime? get ultimaModificacao;

  // Soft Delete: Se true, o SyncService sabe que deve excluir o documento na nuvem.
  bool get isDeletado;

  // Converte o objeto local para JSON (Map) compatível com o Firestore.
  Map<String, dynamic> toMap();
}
