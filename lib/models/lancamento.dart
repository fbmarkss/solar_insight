// Caminho: lib/models/lancamento.dart
// Descrição: Modelo de lançamento mensal (Geração/Fatura).
// Status: COMPLETO (Implementa SyncableModel, criadoPor e Conciliação de Saldo).

import 'package:hive/hive.dart';
import '../interfaces/syncable_model.dart';

@HiveType(typeId: 1)
class LancamentoMensal extends HiveObject implements SyncableModel {
  // --- CAMPOS FUNCIONAIS ---
  @HiveField(0)
  String usinaId;

  @HiveField(1)
  DateTime dataReferencia;

  @HiveField(2)
  double geracaoTotalKwh;

  @HiveField(3)
  double energiaInjetadaKwh;

  @HiveField(4)
  double energiaConsumidaRedeKwh;

  @HiveField(5)
  double tarifaKwh;

  @HiveField(6)
  double valorFaturaR;

  @HiveField(7)
  String? observacao;

  @HiveField(8)
  double? leituraInversor;

  @HiveField(9)
  double custoDemandaR;

  // --- CAMPOS ESTRUTURAIS DE SYNC (SYNCABLE MODEL) ---

  // 1. IDENTIDADE
  @HiveField(10)
  String? idRemoto; // ID no Firestore

  @HiveField(11)
  String? tenantId; // ID DA EMPRESA (Compartilhamento)

  // 2. CONTROLE DE VERSÃO
  @HiveField(12)
  @override
  DateTime? ultimaModificacao;

  // 3. SOFT DELETE
  @HiveField(13)
  @override
  bool isDeletado;

  @HiveField(14)
  String fonteOrigem;

  @HiveField(15)
  String? editadoPor; // Último usuário que editou

  // 4. IDENTIDADE LOCAL
  @HiveField(16)
  @override
  String id;

  // 5. CONTROLE DE SYNC
  @HiveField(17)
  DateTime? ultimaSincronizacao;

  // 6. AUTORIA
  @HiveField(18)
  String? criadoPor; // Usuário criador original (Permissão de Exclusão)

  // 7. CONCILIAÇÃO BANCÁRIA (NOVO)
  @HiveField(19)
  double? saldoInformadoNaFatura; // Saldo oficial vindo da conta para corrigir a rota do App

  LancamentoMensal({
    required this.usinaId,
    required this.dataReferencia,
    required this.geracaoTotalKwh,
    required this.energiaInjetadaKwh,
    required this.energiaConsumidaRedeKwh,
    required this.tarifaKwh,
    required this.valorFaturaR,
    this.observacao,
    this.leituraInversor,
    this.custoDemandaR = 0.0,
    this.idRemoto,
    this.tenantId,
    this.ultimaModificacao,
    this.isDeletado = false,
    this.fonteOrigem = 'MANUAL',
    this.editadoPor,
    String? id,
    this.ultimaSincronizacao,
    this.criadoPor,
    this.saldoInformadoNaFatura, // NOVO
  }) : id =
           id ??
           // Gerador de ID simples: Timestamp + Hash da Usina
           DateTime.now().millisecondsSinceEpoch.toString() +
               usinaId.hashCode.toString();

  // --- GETTERS AUXILIARES ---

  double get saldoEnergeticoKwh => energiaInjetadaKwh - energiaConsumidaRedeKwh;
  double get economiaEstimadaR => (geracaoTotalKwh * tarifaKwh);

  // --- CONVERSÃO JSON (OBRIGATÓRIO PELA INTERFACE) ---

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id, // ID Local
      'usinaId': usinaId,
      'dataReferencia': dataReferencia.millisecondsSinceEpoch,
      'geracaoTotalKwh': geracaoTotalKwh,
      'energiaInjetadaKwh': energiaInjetadaKwh,
      'energiaConsumidaRedeKwh': energiaConsumidaRedeKwh,
      'tarifaKwh': tarifaKwh,
      'valorFaturaR': valorFaturaR,
      'observacao': observacao,
      'leituraInversor': leituraInversor,
      'custoDemandaR': custoDemandaR,
      'idRemoto': idRemoto,
      'tenantId': tenantId,
      'ultimaModificacao': ultimaModificacao?.millisecondsSinceEpoch,
      'isDeletado': isDeletado,
      'fonteOrigem': fonteOrigem,
      'editadoPor': editadoPor,
      'ultimaSincronizacao': ultimaSincronizacao?.millisecondsSinceEpoch,
      'criadoPor': criadoPor,
      'saldoInformadoNaFatura': saldoInformadoNaFatura, // NOVO
    };
  }

  // Factory para criar a partir do JSON
  factory LancamentoMensal.fromMap(Map<String, dynamic> map) {
    return LancamentoMensal(
      id: map['id'],
      usinaId: map['usinaId'] ?? '',
      dataReferencia: DateTime.fromMillisecondsSinceEpoch(
        map['dataReferencia'] ?? DateTime.now().millisecondsSinceEpoch,
      ),
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
      idRemoto: map['idRemoto'],
      tenantId: map['tenantId'],
      ultimaModificacao: map['ultimaModificacao'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['ultimaModificacao'])
          : null,
      isDeletado: map['isDeletado'] ?? false,
      fonteOrigem: map['fonteOrigem'] ?? 'MANUAL',
      editadoPor: map['editadoPor'],
      criadoPor: map['criadoPor'],
      saldoInformadoNaFatura: (map['saldoInformadoNaFatura'] as num?)
          ?.toDouble(), // NOVO
    );
  }
}

// --- ADAPTADOR MANUAL ATUALIZADO (20 CAMPOS: 0 a 19) ---
class LancamentoMensalAdapter extends TypeAdapter<LancamentoMensal> {
  @override
  final int typeId = 1;

  @override
  LancamentoMensal read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };

    String idGerado = fields.containsKey(16)
        ? fields[16] as String
        : DateTime.now().millisecondsSinceEpoch.toString() +
              (fields[0] as String);

    return LancamentoMensal(
      usinaId: fields[0] as String,
      dataReferencia: fields[1] as DateTime,
      geracaoTotalKwh: fields[2] as double,
      energiaInjetadaKwh: fields[3] as double,
      energiaConsumidaRedeKwh: fields[4] as double,
      tarifaKwh: fields[5] as double,
      valorFaturaR: fields[6] as double,
      observacao: fields[7] as String?,
      leituraInversor: fields[8] as double?,
      custoDemandaR: fields.containsKey(9) ? fields[9] as double : 0.0,
      idRemoto: fields.containsKey(10) ? fields[10] as String? : null,
      tenantId: fields.containsKey(11) ? fields[11] as String? : null,
      ultimaModificacao: fields.containsKey(12)
          ? fields[12] as DateTime?
          : DateTime.now(),
      isDeletado: fields.containsKey(13) ? fields[13] as bool : false,
      fonteOrigem: fields.containsKey(14) ? fields[14] as String : 'MANUAL',
      editadoPor: fields.containsKey(15) ? fields[15] as String? : null,
      id: idGerado,
      ultimaSincronizacao: fields.containsKey(17)
          ? fields[17] as DateTime?
          : null,
      criadoPor: fields.containsKey(18) ? fields[18] as String? : null,
      saldoInformadoNaFatura: fields.containsKey(19)
          ? fields[19] as double?
          : null, // NOVO
    );
  }

  @override
  void write(BinaryWriter writer, LancamentoMensal obj) {
    writer
      ..writeByte(20) // Aumentado para 20 campos (0 a 19)
      ..writeByte(0)
      ..write(obj.usinaId)
      ..writeByte(1)
      ..write(obj.dataReferencia)
      ..writeByte(2)
      ..write(obj.geracaoTotalKwh)
      ..writeByte(3)
      ..write(obj.energiaInjetadaKwh)
      ..writeByte(4)
      ..write(obj.energiaConsumidaRedeKwh)
      ..writeByte(5)
      ..write(obj.tarifaKwh)
      ..writeByte(6)
      ..write(obj.valorFaturaR)
      ..writeByte(7)
      ..write(obj.observacao)
      ..writeByte(8)
      ..write(obj.leituraInversor)
      ..writeByte(9)
      ..write(obj.custoDemandaR)
      ..writeByte(10)
      ..write(obj.idRemoto)
      ..writeByte(11)
      ..write(obj.tenantId)
      ..writeByte(12)
      ..write(obj.ultimaModificacao)
      ..writeByte(13)
      ..write(obj.isDeletado)
      ..writeByte(14)
      ..write(obj.fonteOrigem)
      ..writeByte(15)
      ..write(obj.editadoPor)
      ..writeByte(16)
      ..write(obj.id)
      ..writeByte(17)
      ..write(obj.ultimaSincronizacao)
      ..writeByte(18)
      ..write(obj.criadoPor)
      ..writeByte(19) // NOVO CAMPO
      ..write(obj.saldoInformadoNaFatura);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LancamentoMensalAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
