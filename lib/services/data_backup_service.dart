// Caminho: lib/services/data_backup_service.dart
// Status: 100% COMPLETO | Universal (Mobile e Web corrigido) | Fila, Multi-tenancy, Backup JSON Integral com Campos de IA.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/usina.dart';
import '../models/lancamento.dart';
import 'sync_queue_service.dart';

class DataBackupService {
  // --- HELPER: Busca o contexto da empresa do utilizador logado ---
  static Future<Map<String, String>?> _getUserContext() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final empresaId = doc.data()?['empresaId'] ?? user.uid;
      return {'uid': user.uid, 'empresaId': empresaId};
    } catch (e) {
      return {'uid': user.uid, 'empresaId': user.uid};
    }
  }

  // --- HELPER MÁGICO: Lê ficheiros quer na Web (Bytes) quer no Mobile (Path) ---
  static Future<String> _lerConteudoArquivo(FilePickerResult result) async {
    if (kIsWeb) {
      return utf8.decode(result.files.single.bytes!);
    } else {
      File file = File(result.files.single.path!);
      return await file.readAsString();
    }
  }

  // ===========================================================================
  // --- PASSO 1: USINAS (ESTRUTURA + EQUIPAMENTOS BASE) ---
  // ===========================================================================

  static Future<void> exportarEstruturaUsinas(String nomeArquivo) async {
    final boxUsinas = Hive.box<Usina>('usinas');
    List<List<dynamic>> rows = [];

    rows.add([
      "ID_UC",
      "Nome",
      "Concessionaria",
      "Tipo",
      "Ativa",
      "Inversor_Marca",
      "Inversor_Pot_kW",
      "Inversor_Qtd",
      "Painel_Marca",
      "Painel_Pot_W",
      "Painel_Qtd",
    ]);

    for (var u in boxUsinas.values.where((u) => !u.isDeletado)) {
      String invMarca = u.inversores.isNotEmpty ? u.inversores.first.marca : "";
      double invPot = u.inversores.isNotEmpty
          ? u.inversores.first.potenciaKw
          : 0.0;
      int invQtd = u.inversores.isNotEmpty ? u.inversores.first.quantidade : 0;

      String panMarca = u.paineis.isNotEmpty ? u.paineis.first.marca : "";
      double panPot = u.paineis.isNotEmpty
          ? u.paineis.first.potenciaWatts
          : 0.0;
      int panQtd = u.paineis.isNotEmpty ? u.paineis.first.quantidade : 0;

      rows.add([
        u.id,
        u.nome,
        u.concessionaria,
        u.tipo,
        u.ativa ? "SIM" : "NAO",
        invMarca,
        invPot > 0 ? invPot.toString().replaceAll('.', ',') : "",
        invQtd > 0 ? invQtd : "",
        panMarca,
        panPot > 0 ? panPot.toString().replaceAll('.', ',') : "",
        panQtd > 0 ? panQtd : "",
      ]);
    }

    String csvData = const ListToCsvConverter(
      fieldDelimiter: ';',
    ).convert(rows);
    final Uint8List bytes = Uint8List.fromList(
      [0xEF, 0xBB, 0xBF] + utf8.encode(csvData),
    );

    if (kIsWeb) {
      await FileSaver.instance.saveFile(
        name: nomeArquivo,
        bytes: bytes,
        ext: 'csv',
        mimeType: MimeType.csv,
      );
    } else {
      await FileSaver.instance.saveAs(
        name: nomeArquivo,
        bytes: bytes,
        ext: 'csv',
        mimeType: MimeType.csv,
      );
    }
  }

  static Future<String> importarEstruturaUsinas() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: kIsWeb,
    );

    if (result == null) return "Cancelado";

    final userCtx = await _getUserContext();
    if (userCtx == null) throw Exception("Utilizador não autenticado.");
    final agora = DateTime.now();

    String content = await _lerConteudoArquivo(result);
    List<List<dynamic>> rows = const CsvToListConverter(
      fieldDelimiter: ';',
    ).convert(content);

    final boxUsinas = Hive.box<Usina>('usinas');
    int importados = 0;

    for (int i = 1; i < rows.length; i++) {
      var row = rows[i];
      if (row.length < 4) continue;

      final idUc = row[0].toString().trim();
      if (!boxUsinas.values.any((u) => u.id == idUc)) {
        List<InversorItem> inversoresIniciais = [];
        List<PainelItem> paineisIniciais = [];

        if (row.length >= 11) {
          String invMarca = row[5].toString().trim();
          double invPot = _parseDouble(row[6]);
          int invQtd = int.tryParse(row[7].toString()) ?? 1;

          String panMarca = row[8].toString().trim();
          double panPot = _parseDouble(row[9]);
          int panQtd = int.tryParse(row[10].toString()) ?? 1;

          if (invMarca.isNotEmpty && invPot > 0) {
            inversoresIniciais.add(
              InversorItem(
                marca: invMarca,
                potenciaKw: invPot,
                quantidade: invQtd,
              ),
            );
          }
          if (panMarca.isNotEmpty && panPot > 0) {
            paineisIniciais.add(
              PainelItem(
                marca: panMarca,
                potenciaWatts: panPot,
                quantidade: panQtd,
              ),
            );
          }
        }

        final nova = Usina(
          id: idUc,
          nome: row[1].toString().trim(),
          concessionaria: row[2].toString().trim(),
          tipo: row[3].toString().trim(),
          ativa: row[4].toString().trim().toUpperCase() == "SIM",
          inversores: inversoresIniciais,
          paineis: paineisIniciais,
          investimentos: [],
          beneficiarias: [],
          tenantId: userCtx['empresaId'],
          criadoPor: userCtx['uid'],
          ultimaSincronizacao: agora,
        );

        await boxUsinas.add(nova);
        await SyncQueueService.enqueue('usinas', nova.id);
        importados++;
      }
    }
    return "Sucesso! $importados usinas registadas e enviadas para sync.";
  }

  // ===========================================================================
  // --- PASSO 2: LANÇAMENTOS (DADOS) ---
  // ===========================================================================

  static Future<void> exportarRelatorioCsv(String nomeArquivo) async {
    final boxUsinas = Hive.box<Usina>('usinas');
    final boxLancamentos = Hive.box<LancamentoMensal>('lancamentos');

    List<List<dynamic>> rows = [];
    // O Relatório CSV simples não exporta tudo, é só pra visualização do utilizador. O Backup JSON é que faz o trabalho pesado.
    rows.add([
      "ID_UC",
      "Nome da Usina",
      "Data Ref",
      "Geração",
      "Injetada",
      "Consumo",
      "Tarifa Média",
      "Fatura",
      "Demanda",
      "Leitura Inversor",
    ]);

    final lancamentos = boxLancamentos.values
        .where((l) => !l.isDeletado)
        .toList();
    lancamentos.sort((a, b) => b.dataReferencia.compareTo(a.dataReferencia));

    for (var l in lancamentos) {
      String nomeUsina = "Desconhecida";
      try {
        nomeUsina = boxUsinas.values.firstWhere((u) => u.id == l.usinaId).nome;
      } catch (_) {}

      rows.add([
        l.usinaId,
        nomeUsina,
        DateFormat('dd/MM/yyyy').format(l.dataReferencia),
        l.geracaoTotalKwh.toString().replaceAll('.', ','),
        l.energiaInjetadaKwh.toString().replaceAll('.', ','),
        l.energiaConsumidaRedeKwh.toString().replaceAll('.', ','),
        l.tarifaKwh.toString().replaceAll('.', ','),
        l.valorFaturaR.toString().replaceAll('.', ','),
        l.custoDemandaR.toString().replaceAll('.', ','),
        (l.leituraInversor ?? 0.0).toString().replaceAll('.', ','),
      ]);
    }

    String csvData = const ListToCsvConverter(
      fieldDelimiter: ';',
    ).convert(rows);
    final Uint8List bytes = Uint8List.fromList(
      [0xEF, 0xBB, 0xBF] + utf8.encode(csvData),
    );

    if (kIsWeb) {
      await FileSaver.instance.saveFile(
        name: nomeArquivo,
        bytes: bytes,
        ext: 'csv',
        mimeType: MimeType.csv,
      );
    } else {
      await FileSaver.instance.saveAs(
        name: nomeArquivo,
        bytes: bytes,
        ext: 'csv',
        mimeType: MimeType.csv,
      );
    }
  }

  static Future<String> importarCsvEmMassa() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: kIsWeb,
    );
    if (result == null) return "Cancelado";

    final userCtx = await _getUserContext();
    if (userCtx == null) throw Exception("Utilizador não autenticado.");
    final agora = DateTime.now();

    String content = await _lerConteudoArquivo(result);
    List<List<dynamic>> rows = const CsvToListConverter(
      fieldDelimiter: ';',
    ).convert(content);

    final boxLancamentos = Hive.box<LancamentoMensal>('lancamentos');
    final boxUsinas = Hive.box<Usina>('usinas');
    int importados = 0;

    for (int i = 1; i < rows.length; i++) {
      var row = rows[i];
      if (row.length < 7) continue;

      String idUc = row[0].toString().trim();

      if (boxUsinas.values.any((u) => u.id == idUc)) {
        DateTime dataRef = _parseData(row[2]);

        bool jaExiste = boxLancamentos.values.any(
          (l) =>
              l.usinaId == idUc &&
              l.dataReferencia.month == dataRef.month &&
              l.dataReferencia.year == dataRef.year &&
              !l.isDeletado,
        );

        if (!jaExiste) {
          final novoLanc = LancamentoMensal(
            usinaId: idUc,
            dataReferencia: dataRef,
            geracaoTotalKwh: _parseDouble(row[3]),
            energiaInjetadaKwh: _parseDouble(row[4]),
            energiaConsumidaRedeKwh: _parseDouble(row[5]),
            tarifaKwh: _parseDouble(row[6]),
            valorFaturaR: _parseDouble(row[7]),
            custoDemandaR: row.length > 8 ? _parseDouble(row[8]) : 0.0,
            leituraInversor: row.length > 9 ? _parseDouble(row[9]) : 0.0,
            tenantId: userCtx['empresaId'],
            criadoPor: userCtx['uid'],
            ultimaModificacao: agora,
          );

          await boxLancamentos.add(novoLanc);
          await SyncQueueService.enqueue('lancamentos', novoLanc.id);
          importados++;
        }
      }
    }
    return "Sucesso! $importados faturas importadas e na fila de sync.";
  }

  // ===========================================================================
  // --- BACKUP COMPLETO (JSON) INTEGRAL (COM CAMPOS DA IA) ---
  // ===========================================================================

  static Future<void> exportarBackupJson(String nomeArquivo) async {
    final boxUsinas = Hive.box<Usina>('usinas');
    final boxLancamentos = Hive.box<LancamentoMensal>('lancamentos');

    final usinasMap = boxUsinas.values
        .where((u) => !u.isDeletado)
        .map(
          (u) => {
            'id': u.id,
            'nome': u.nome,
            'concessionaria': u.concessionaria,
            'tipo': u.tipo,
            'ativa': u.ativa,
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
                    'data': inv.data.toIso8601String(),
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
                  },
                )
                .toList(),
          },
        )
        .toList();

    final lancamentosMap = boxLancamentos.values
        .where((l) => !l.isDeletado)
        .map(
          (l) => {
            'usinaId': l.usinaId,
            'dataReferencia': l.dataReferencia.toIso8601String(),
            'geracaoTotalKwh': l.geracaoTotalKwh,
            'energiaInjetadaKwh': l.energiaInjetadaKwh,
            'energiaConsumidaRedeKwh': l.energiaConsumidaRedeKwh,
            'tarifaKwh': l.tarifaKwh,
            'valorFaturaR': l.valorFaturaR,
            'custoDemandaR': l.custoDemandaR,
            'leituraInversor': l.leituraInversor,
            'observacao': l.observacao,
            // --- NOVOS CAMPOS DA IA ADICIONADOS AQUI ---
            'grupoTarifario': l.grupoTarifario,
            'modalidadeTarifaria': l.modalidadeTarifaria,
            'tarifaTeUnica': l.tarifaTeUnica,
            'tarifaTusdUnica': l.tarifaTusdUnica,
            'tarifaTePonta': l.tarifaTePonta,
            'tarifaTusdPonta': l.tarifaTusdPonta,
            'tarifaTeForaPonta': l.tarifaTeForaPonta,
            'tarifaTusdForaPonta': l.tarifaTusdForaPonta,
            'custoIluminacaoPublica': l.custoIluminacaoPublica,
            'multaReativo': l.multaReativo,
            'saldoInformadoNaFatura': l.saldoInformadoNaFatura,
            // ---------------------------------------------
          },
        )
        .toList();

    final backupData = {
      'versao': '1.3', // Subimos a versão do Backup por ter novos campos
      'dataBackup': DateTime.now().toIso8601String(),
      'usinas': usinasMap,
      'lancamentos': lancamentosMap,
    };

    final Uint8List bytes = Uint8List.fromList(
      utf8.encode(jsonEncode(backupData)),
    );

    if (kIsWeb) {
      await FileSaver.instance.saveFile(
        name: nomeArquivo,
        bytes: bytes,
        ext: 'json',
        mimeType: MimeType.json,
      );
    } else {
      await FileSaver.instance.saveAs(
        name: nomeArquivo,
        bytes: bytes,
        ext: 'json',
        mimeType: MimeType.json,
      );
    }
  }

  static Future<String> restaurarBackupJson() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: kIsWeb,
    );
    if (result == null) return "Cancelado";

    final userCtx = await _getUserContext();
    if (userCtx == null) throw Exception("Utilizador não autenticado.");
    final agora = DateTime.now();

    String content = await _lerConteudoArquivo(result);
    Map<String, dynamic> data = jsonDecode(content);

    final boxUsinas = Hive.box<Usina>('usinas');
    final boxLancamentos = Hive.box<LancamentoMensal>('lancamentos');

    // 1. Limpa dados locais via Soft Delete
    for (var key in boxUsinas.keys) {
      final u = boxUsinas.get(key);
      if (u != null && !u.isDeletado) {
        u.isDeletado = true;
        u.ultimaSincronizacao = agora;
        await u.save();
        await SyncQueueService.enqueue('usinas', u.id);
      }
    }

    for (var key in boxLancamentos.keys) {
      final l = boxLancamentos.get(key);
      if (l != null && !l.isDeletado) {
        l.isDeletado = true;
        l.ultimaModificacao = agora;
        await l.save();
        await SyncQueueService.enqueue('lancamentos', l.id);
      }
    }

    // 2. Insere dados do JSON
    int countUsinas = 0;
    int countLancamentos = 0;

    if (data['usinas'] != null) {
      for (var uMap in data['usinas']) {
        List<InversorItem> invList = [];
        List<PainelItem> panList = [];
        List<InvestimentoItem> invCustosList = [];
        List<BeneficiariaItem> benList = [];

        if (uMap['inversores'] != null) {
          for (var i in uMap['inversores']) {
            invList.add(
              InversorItem(
                marca: i['marca'],
                potenciaKw: (i['potenciaKw'] as num).toDouble(),
                quantidade: i['quantidade'],
              ),
            );
          }
        }

        if (uMap['paineis'] != null) {
          for (var p in uMap['paineis']) {
            panList.add(
              PainelItem(
                marca: p['marca'],
                potenciaWatts: (p['potenciaWatts'] as num).toDouble(),
                quantidade: p['quantidade'],
              ),
            );
          }
        }

        if (uMap['investimentos'] != null) {
          for (var inv in uMap['investimentos']) {
            invCustosList.add(
              InvestimentoItem(
                data: DateTime.parse(inv['data']),
                descricao: inv['descricao'],
                valor: (inv['valor'] as num).toDouble(),
              ),
            );
          }
        }

        if (uMap['beneficiarias'] != null) {
          for (var ben in uMap['beneficiarias']) {
            benList.add(
              BeneficiariaItem(
                nome: ben['nome'],
                idUsinaFilha: ben['idUsinaFilha'],
                percentual: (ben['percentual'] as num).toDouble(),
              ),
            );
          }
        }

        final nova = Usina(
          id: uMap['id'],
          nome: uMap['nome'],
          concessionaria: uMap['concessionaria'],
          tipo: uMap['tipo'],
          ativa: uMap['ativa'],
          inversores: invList,
          paineis: panList,
          investimentos: invCustosList,
          beneficiarias: benList,
          tenantId: userCtx['empresaId'],
          criadoPor: userCtx['uid'],
          ultimaSincronizacao: agora,
        );
        await boxUsinas.add(nova);
        await SyncQueueService.enqueue('usinas', nova.id);
        countUsinas++;
      }
    }

    if (data['lancamentos'] != null) {
      for (var lMap in data['lancamentos']) {
        final novo = LancamentoMensal(
          usinaId: lMap['usinaId'],
          dataReferencia: DateTime.parse(lMap['dataReferencia']),
          geracaoTotalKwh: (lMap['geracaoTotalKwh'] as num).toDouble(),
          energiaInjetadaKwh: (lMap['energiaInjetadaKwh'] as num).toDouble(),
          energiaConsumidaRedeKwh: (lMap['energiaConsumidaRedeKwh'] as num)
              .toDouble(),
          tarifaKwh: (lMap['tarifaKwh'] as num).toDouble(),
          valorFaturaR: (lMap['valorFaturaR'] as num).toDouble(),
          custoDemandaR: (lMap['custoDemandaR'] as num).toDouble(),
          leituraInversor: (lMap['leituraInversor'] as num?)?.toDouble(),
          observacao: lMap['observacao'],
          // --- LEITURA DOS NOVOS CAMPOS DA IA (COM PROTEÇÃO CONTRA BACKUPS ANTIGOS) ---
          grupoTarifario: lMap['grupoTarifario'],
          modalidadeTarifaria: lMap['modalidadeTarifaria'],
          tarifaTeUnica: (lMap['tarifaTeUnica'] as num?)?.toDouble(),
          tarifaTusdUnica: (lMap['tarifaTusdUnica'] as num?)?.toDouble(),
          tarifaTePonta: (lMap['tarifaTePonta'] as num?)?.toDouble(),
          tarifaTusdPonta: (lMap['tarifaTusdPonta'] as num?)?.toDouble(),
          tarifaTeForaPonta: (lMap['tarifaTeForaPonta'] as num?)?.toDouble(),
          tarifaTusdForaPonta: (lMap['tarifaTusdForaPonta'] as num?)
              ?.toDouble(),
          custoIluminacaoPublica: (lMap['custoIluminacaoPublica'] as num?)
              ?.toDouble(),
          multaReativo: (lMap['multaReativo'] as num?)?.toDouble(),
          saldoInformadoNaFatura: (lMap['saldoInformadoNaFatura'] as num?)
              ?.toDouble(),
          // ----------------------------------------------------------------------------
          tenantId: userCtx['empresaId'],
          criadoPor: userCtx['uid'],
          ultimaModificacao: agora,
        );
        await boxLancamentos.add(novo);
        await SyncQueueService.enqueue('lancamentos', novo.id);
        countLancamentos++;
      }
    }

    return "Backup Restaurado! $countUsinas Usinas e $countLancamentos Faturas inseridas e enviadas para sync.";
  }

  // ===========================================================================
  // --- HELPERS (CONVERSORES) ---
  // ===========================================================================

  static double _parseDouble(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) return 0.0;
    String s = value
        .toString()
        .replaceAll('.', '')
        .replaceAll(',', '.')
        .replaceAll(RegExp(r'[^\d.-]'), '');
    return double.tryParse(s) ?? 0.0;
  }

  static DateTime _parseData(dynamic value) {
    try {
      return DateFormat('dd/MM/yyyy').parse(value.toString().trim());
    } catch (_) {
      return DateTime.now();
    }
  }
}
