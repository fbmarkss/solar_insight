// Caminho: lib/models/usina.dart
// Descrição: Modelo de dados da Usina (Atualizado para Multi-tenancy, Autoria e Histórico de Rateio).

import 'package:hive/hive.dart';

// Constantes de Tipo
const String tipoGeradora = 'GERADORA';
const String tipoBeneficiaria = 'BENEFICIARIA';

@HiveType(typeId: 0)
class Usina extends HiveObject {
  // --- CAMPOS FUNCIONAIS (USADOS HOJE) ---
  @HiveField(0)
  String id; // UUID Local

  @HiveField(1)
  String nome;

  @HiveField(2)
  String concessionaria;

  @HiveField(3)
  String tipo;

  @HiveField(4)
  bool ativa;

  @HiveField(5)
  List<InversorItem> inversores;

  @HiveField(6)
  List<PainelItem> paineis;

  @HiveField(7)
  List<InvestimentoItem> investimentos;

  @HiveField(8)
  List<BeneficiariaItem> beneficiarias;

  // --- CAMPOS ESTRUTURAIS ---

  // 1. IDENTIDADE NA NUVEM
  @HiveField(9)
  String? idRemoto; // ID do documento no Firebase.

  // 2. MULTI-TENANCY (EMPRESA)
  @HiveField(10)
  String? tenantId; // ID da Empresa (Todos com mesmo tenantId veem os dados).

  // 3. COMPARTILHAMENTO
  @HiveField(11)
  List<String>? compartilhadoCom;

  // 4. SINCRONIZAÇÃO
  @HiveField(12)
  DateTime? ultimaSincronizacao;

  @HiveField(13)
  bool isDeletado;

  // 5. AUTORIA (NOVO)
  @HiveField(14)
  String? criadoPor; // ID do Usuário que criou (Para permissão de exclusão).

  Usina({
    required this.id,
    required this.nome,
    required this.concessionaria,
    required this.tipo,
    this.ativa = true,
    this.inversores = const [],
    this.paineis = const [],
    this.investimentos = const [],
    this.beneficiarias = const [],
    // Defaults para o futuro
    this.idRemoto,
    this.tenantId,
    this.compartilhadoCom,
    this.ultimaSincronizacao,
    this.isDeletado = false,
    this.criadoPor, // NOVO
  });

  // --- GETTERS AUXILIARES ---
  bool get isGeradora => tipo == tipoGeradora;
  bool get isBeneficiaria => tipo == tipoBeneficiaria;

  double get potenciaTotalInversoresKw => inversores.fold(
    0,
    (sum, item) => sum + (item.potenciaKw * item.quantidade),
  );

  double get potenciaTotalPaineisKwp => paineis.fold(
    0,
    (sum, item) => sum + ((item.potenciaWatts * item.quantidade) / 1000),
  );

  double get totalInvestido =>
      investimentos.fold(0, (sum, item) => sum + item.valor);

  // --- GETTER PARA O USINA CARD ---
  String get resumoEquipamentos {
    if (isBeneficiaria) return "Unidade Beneficiária";
    if (inversores.isEmpty && paineis.isEmpty) return "Sem equipamentos";

    String textoInv = "";
    if (inversores.isNotEmpty) {
      textoInv = "${potenciaTotalInversoresKw.toStringAsFixed(1)} kW";
    }

    String textoPainel = "";
    if (paineis.isNotEmpty) {
      int qtd = paineis.fold(0, (sum, item) => sum + item.quantidade);
      textoPainel = "$qtd x Painéis";
    }

    if (textoInv.isNotEmpty && textoPainel.isNotEmpty) {
      return "$textoInv • $textoPainel";
    }
    return textoInv.isNotEmpty ? textoInv : textoPainel;
  }
}

// --- SUB-CLASSES (ITENS) ---

@HiveType(typeId: 2)
class InversorItem extends HiveObject {
  @HiveField(0)
  String marca;
  @HiveField(1)
  double potenciaKw;
  @HiveField(2)
  int quantidade;

  InversorItem({
    required this.marca,
    required this.potenciaKw,
    required this.quantidade,
  });
}

@HiveType(typeId: 3)
class PainelItem extends HiveObject {
  @HiveField(0)
  String marca;
  @HiveField(1)
  double potenciaWatts;
  @HiveField(2)
  int quantidade;

  PainelItem({
    required this.marca,
    required this.potenciaWatts,
    required this.quantidade,
  });
}

@HiveType(typeId: 4)
class InvestimentoItem extends HiveObject {
  @HiveField(0)
  DateTime data;
  @HiveField(1)
  String descricao;
  @HiveField(2)
  double valor;

  InvestimentoItem({
    required this.data,
    required this.descricao,
    required this.valor,
  });
}

@HiveType(typeId: 5)
class BeneficiariaItem extends HiveObject {
  @HiveField(0)
  String nome;

  @HiveField(1)
  String idUsinaFilha;

  @HiveField(2)
  double percentual;

  // --- NOVOS CAMPOS: HISTÓRICO DE VIGÊNCIA ---
  @HiveField(3)
  DateTime dataInicio;

  @HiveField(4)
  DateTime? dataFim;

  BeneficiariaItem({
    required this.nome,
    required this.idUsinaFilha,
    required this.percentual,
    required this.dataInicio, // Agora é obrigatório
    this.dataFim, // Nulo = Vigente atual
  });
}

// --- ADAPTADORES MANUAIS ---

class UsinaAdapter extends TypeAdapter<Usina> {
  @override
  final int typeId = 0;

  @override
  Usina read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Usina(
      id: fields[0] as String,
      nome: fields[1] as String,
      concessionaria: fields[2] as String,
      tipo: fields[3] as String,
      ativa: fields[4] as bool,
      inversores: (fields[5] as List).cast<InversorItem>(),
      paineis: (fields[6] as List).cast<PainelItem>(),
      investimentos: (fields[7] as List).cast<InvestimentoItem>(),
      beneficiarias: (fields[8] as List).cast<BeneficiariaItem>(),
      // Leitura segura dos novos campos
      idRemoto: fields.containsKey(9) ? fields[9] as String? : null,
      tenantId: fields.containsKey(10) ? fields[10] as String? : null,
      compartilhadoCom: fields.containsKey(11)
          ? (fields[11] as List?)?.cast<String>()
          : [],
      ultimaSincronizacao: fields.containsKey(12)
          ? fields[12] as DateTime?
          : null,
      isDeletado: fields.containsKey(13) ? fields[13] as bool : false,
      criadoPor: fields.containsKey(14) ? fields[14] as String? : null, // NOVO
    );
  }

  @override
  void write(BinaryWriter writer, Usina obj) {
    writer
      ..writeByte(15) // Aumentado para 15 campos
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.nome)
      ..writeByte(2)
      ..write(obj.concessionaria)
      ..writeByte(3)
      ..write(obj.tipo)
      ..writeByte(4)
      ..write(obj.ativa)
      ..writeByte(5)
      ..write(obj.inversores)
      ..writeByte(6)
      ..write(obj.paineis)
      ..writeByte(7)
      ..write(obj.investimentos)
      ..writeByte(8)
      ..write(obj.beneficiarias)
      ..writeByte(9)
      ..write(obj.idRemoto)
      ..writeByte(10)
      ..write(obj.tenantId)
      ..writeByte(11)
      ..write(obj.compartilhadoCom)
      ..writeByte(12)
      ..write(obj.ultimaSincronizacao)
      ..writeByte(13)
      ..write(obj.isDeletado)
      ..writeByte(14) // NOVO
      ..write(obj.criadoPor);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsinaAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class InversorItemAdapter extends TypeAdapter<InversorItem> {
  @override
  final int typeId = 2;
  @override
  InversorItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return InversorItem(
      marca: fields[0] as String,
      potenciaKw: fields[1] as double,
      quantidade: fields[2] as int,
    );
  }

  @override
  void write(BinaryWriter writer, InversorItem obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.marca)
      ..writeByte(1)
      ..write(obj.potenciaKw)
      ..writeByte(2)
      ..write(obj.quantidade);
  }

  @override
  int get hashCode => typeId.hashCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InversorItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class PainelItemAdapter extends TypeAdapter<PainelItem> {
  @override
  final int typeId = 3;
  @override
  PainelItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PainelItem(
      marca: fields[0] as String,
      potenciaWatts: fields[1] as double,
      quantidade: fields[2] as int,
    );
  }

  @override
  void write(BinaryWriter writer, PainelItem obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.marca)
      ..writeByte(1)
      ..write(obj.potenciaWatts)
      ..writeByte(2)
      ..write(obj.quantidade);
  }

  @override
  int get hashCode => typeId.hashCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PainelItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class InvestimentoItemAdapter extends TypeAdapter<InvestimentoItem> {
  @override
  final int typeId = 4;
  @override
  InvestimentoItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return InvestimentoItem(
      data: fields[0] as DateTime,
      descricao: fields[1] as String,
      valor: fields[2] as double,
    );
  }

  @override
  void write(BinaryWriter writer, InvestimentoItem obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.data)
      ..writeByte(1)
      ..write(obj.descricao)
      ..writeByte(2)
      ..write(obj.valor);
  }

  @override
  int get hashCode => typeId.hashCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InvestimentoItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class BeneficiariaItemAdapter extends TypeAdapter<BeneficiariaItem> {
  @override
  final int typeId = 5;

  @override
  BeneficiariaItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BeneficiariaItem(
      nome: fields[0] as String,
      idUsinaFilha: fields[1] as String,
      percentual: fields[2] as double,
      // Fallback para dados antigos: Aplica o rateio desde o ano 2000
      dataInicio: fields.containsKey(3)
          ? fields[3] as DateTime
          : DateTime(2000, 1, 1),
      dataFim: fields.containsKey(4) ? fields[4] as DateTime? : null,
    );
  }

  @override
  void write(BinaryWriter writer, BeneficiariaItem obj) {
    writer
      ..writeByte(5) // ATENÇÃO: Aumentado para 5 campos
      ..writeByte(0)
      ..write(obj.nome)
      ..writeByte(1)
      ..write(obj.idUsinaFilha)
      ..writeByte(2)
      ..write(obj.percentual)
      ..writeByte(3) // NOVO CAMPO
      ..write(obj.dataInicio)
      ..writeByte(4) // NOVO CAMPO
      ..write(obj.dataFim);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BeneficiariaItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
