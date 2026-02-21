// Caminho: lib/models/lancamento.dart
// Descrição: Modelo de lançamento mensal.
// Status: COMPLETO (Preparado para IA e Sincronização Padronizada).

import 'package:hive/hive.dart';
import '../interfaces/syncable_model.dart';

@HiveType(typeId: 1)
class LancamentoMensal extends HiveObject implements SyncableModel {
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
  @HiveField(10)
  String? idRemoto;
  @HiveField(11)
  String? tenantId;
  @HiveField(12)
  @override
  DateTime? ultimaModificacao;
  @HiveField(13)
  @override
  bool isDeletado;
  @HiveField(14)
  String fonteOrigem;
  @HiveField(15)
  String? editadoPor;
  @HiveField(16)
  @override
  String id;
  @HiveField(17)
  DateTime? ultimaSincronizacao;
  @HiveField(18)
  String? criadoPor;
  @HiveField(19)
  double? saldoInformadoNaFatura;

  // --- CAMPOS IA ---
  @HiveField(20)
  String? grupoTarifario;
  @HiveField(21)
  String? modalidadeTarifaria;
  @HiveField(22)
  double? consumoPonta;
  @HiveField(23)
  double? consumoForaPonta;
  @HiveField(24)
  double? consumoReservado;
  @HiveField(25)
  double? injetadaPonta;
  @HiveField(26)
  double? injetadaForaPonta;
  @HiveField(27)
  double? injetadaReservada;
  @HiveField(28)
  double? tarifaTeUnica;
  @HiveField(29)
  double? tarifaTusdUnica;
  @HiveField(30)
  double? tarifaTePonta;
  @HiveField(31)
  double? tarifaTusdPonta;
  @HiveField(32)
  double? tarifaTeForaPonta;
  @HiveField(33)
  double? tarifaTusdForaPonta;
  @HiveField(34)
  double? custoIluminacaoPublica;
  @HiveField(35)
  double? multaReativo;

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
    this.saldoInformadoNaFatura,
    this.grupoTarifario,
    this.modalidadeTarifaria,
    this.consumoPonta,
    this.consumoForaPonta,
    this.consumoReservado,
    this.injetadaPonta,
    this.injetadaForaPonta,
    this.injetadaReservada,
    this.tarifaTeUnica,
    this.tarifaTusdUnica,
    this.tarifaTePonta,
    this.tarifaTusdPonta,
    this.tarifaTeForaPonta,
    this.tarifaTusdForaPonta,
    this.custoIluminacaoPublica,
    this.multaReativo,
  }) : id =
           id ??
           DateTime.now().millisecondsSinceEpoch.toString() +
               usinaId.hashCode.toString();

  double get saldoEnergeticoKwh => energiaInjetadaKwh - energiaConsumidaRedeKwh;
  double get economiaEstimadaR => (geracaoTotalKwh * tarifaKwh);

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
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
      'saldoInformadoNaFatura': saldoInformadoNaFatura,
      'grupoTarifario': grupoTarifario,
      'modalidadeTarifaria': modalidadeTarifaria,
      'consumoPonta': consumoPonta,
      'consumoForaPonta': consumoForaPonta,
      'consumoReservado': consumoReservado,
      'injetadaPonta': injetadaPonta,
      'injetadaForaPonta': injetadaForaPonta,
      'injetadaReservada': injetadaReservada,
      'tarifaTeUnica': tarifaTeUnica,
      'tarifaTusdUnica': tarifaTusdUnica,
      'tarifaTePonta': tarifaTePonta,
      'tarifaTusdPonta': tarifaTusdPonta,
      'tarifaTeForaPonta': tarifaTeForaPonta,
      'tarifaTusdForaPonta': tarifaTusdForaPonta,
      'custoIluminacaoPublica': custoIluminacaoPublica,
      'multaReativo': multaReativo,
    };
  }
}

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
          : null,
      grupoTarifario: fields.containsKey(20) ? fields[20] as String? : null,
      modalidadeTarifaria: fields.containsKey(21)
          ? fields[21] as String?
          : null,
      consumoPonta: fields.containsKey(22) ? fields[22] as double? : null,
      consumoForaPonta: fields.containsKey(23) ? fields[23] as double? : null,
      consumoReservado: fields.containsKey(24) ? fields[24] as double? : null,
      injetadaPonta: fields.containsKey(25) ? fields[25] as double? : null,
      injetadaForaPonta: fields.containsKey(26) ? fields[26] as double? : null,
      injetadaReservada: fields.containsKey(27) ? fields[27] as double? : null,
      tarifaTeUnica: fields.containsKey(28) ? fields[28] as double? : null,
      tarifaTusdUnica: fields.containsKey(29) ? fields[29] as double? : null,
      tarifaTePonta: fields.containsKey(30) ? fields[30] as double? : null,
      tarifaTusdPonta: fields.containsKey(31) ? fields[31] as double? : null,
      tarifaTeForaPonta: fields.containsKey(32) ? fields[32] as double? : null,
      tarifaTusdForaPonta: fields.containsKey(33)
          ? fields[33] as double?
          : null,
      custoIluminacaoPublica: fields.containsKey(34)
          ? fields[34] as double?
          : null,
      multaReativo: fields.containsKey(35) ? fields[35] as double? : null,
    );
  }

  @override
  void write(BinaryWriter writer, LancamentoMensal obj) {
    writer
      ..writeByte(36)
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
      ..writeByte(19)
      ..write(obj.saldoInformadoNaFatura)
      ..writeByte(20)
      ..write(obj.grupoTarifario)
      ..writeByte(21)
      ..write(obj.modalidadeTarifaria)
      ..writeByte(22)
      ..write(obj.consumoPonta)
      ..writeByte(23)
      ..write(obj.consumoForaPonta)
      ..writeByte(24)
      ..write(obj.consumoReservado)
      ..writeByte(25)
      ..write(obj.injetadaPonta)
      ..writeByte(26)
      ..write(obj.injetadaForaPonta)
      ..writeByte(27)
      ..write(obj.injetadaReservada)
      ..writeByte(28)
      ..write(obj.tarifaTeUnica)
      ..writeByte(29)
      ..write(obj.tarifaTusdUnica)
      ..writeByte(30)
      ..write(obj.tarifaTePonta)
      ..writeByte(31)
      ..write(obj.tarifaTusdPonta)
      ..writeByte(32)
      ..write(obj.tarifaTeForaPonta)
      ..writeByte(33)
      ..write(obj.tarifaTusdForaPonta)
      ..writeByte(34)
      ..write(obj.custoIluminacaoPublica)
      ..writeByte(35)
      ..write(obj.multaReativo);
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
