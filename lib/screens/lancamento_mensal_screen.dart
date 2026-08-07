// Caminho: lib/screens/lancamento_mensal_screen.dart
// Descrição: Tela de Lançamento COMPLETA com UI Mutante (Modo Simples vs Modo IA).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/usina.dart';
import '../models/lancamento.dart';
import '../utils/app_feedback.dart';
import '../services/logger_service.dart';
import '../services/sync_queue_service.dart';
import 'cadastro_usina_screen.dart';
import 'importacao_ia_screen.dart';

class LancamentoMensalScreen extends StatefulWidget {
  final Usina? usinaPreSelecionada;
  final LancamentoMensal? lancamentoParaEditar;

  const LancamentoMensalScreen({
    super.key,
    this.usinaPreSelecionada,
    this.lancamentoParaEditar,
  });

  @override
  State<LancamentoMensalScreen> createState() => _LancamentoMensalScreenState();
}

class _LancamentoMensalScreenState extends State<LancamentoMensalScreen> {
  final _formKey = GlobalKey<FormState>();
  final _logger = LoggerService();

  final _leituraAnteriorController = TextEditingController();
  final _leituraAtualController = TextEditingController();
  final _geracaoController = TextEditingController();
  final _injetadaController = TextEditingController();
  final _creditosTerceirosController = TextEditingController();
  final _consumoController = TextEditingController();
  final _tarifaController = TextEditingController();
  final _custoDemandaController = TextEditingController();
  final _valorFaturaController = TextEditingController();
  final _saldoAcumuladoController = TextEditingController();

  bool _temDadosAvancados = false;
  String? _grupoTarifario;
  String? _modalidadeTarifaria;
  double _teUnica = 0, _tusdUnica = 0;
  double _tePonta = 0, _tusdPonta = 0, _teForaPonta = 0, _tusdForaPonta = 0;
  double _multaReativo = 0, _custoIluminacaoPublica = 0, _demandaIA = 0;
  double _consumoPonta = 0, _consumoForaPonta = 0, _consumoReservado = 0;
  double _injetadaPonta = 0, _injetadaForaPonta = 0, _injetadaReservada = 0;
  double _saldoAnteriorIA = 0.0;

  Usina? _usinaSelecionada;
  DateTime _dataReferencia = DateTime.now();
  bool _manterNaTela = false;
  String? _avisoDuplicidade;
  bool _isEditando = false;

  bool _isAdmin = false;
  String _currentUid = '';

  @override
  void initState() {
    super.initState();
    _currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _carregarPermissoes();

    _usinaSelecionada = widget.usinaPreSelecionada;
    _isEditando = widget.lancamentoParaEditar != null;

    _leituraAtualController.addListener(_calcularGeracao);
    _leituraAnteriorController.addListener(_calcularGeracao);

    if (_isEditando) {
      _carregarDadosParaEdicao();
    } else if (_usinaSelecionada != null) {
      _buscarLeituraAnterior();
    }
  }

  @override
  void dispose() {
    _leituraAtualController.removeListener(_calcularGeracao);
    _leituraAnteriorController.removeListener(_calcularGeracao);
    _leituraAnteriorController.dispose();
    _leituraAtualController.dispose();
    _geracaoController.dispose();
    _injetadaController.dispose();
    _creditosTerceirosController.dispose();
    _consumoController.dispose();
    _tarifaController.dispose();
    _custoDemandaController.dispose();
    _valorFaturaController.dispose();
    _saldoAcumuladoController.dispose();
    super.dispose();
  }

  Future<void> _carregarPermissoes() async {
    if (_currentUid.isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUid)
            .get();
        if (mounted) {
          setState(() => _isAdmin = doc.data()?['role'] == 'admin');
        }
      } catch (e) {
        debugPrint("Erro ao carregar permissões: $e");
      }
    }
  }

  void _carregarDadosParaEdicao() {
    final l = widget.lancamentoParaEditar!;
    final boxUsinas = Hive.box<Usina>('usinas');

    try {
      _usinaSelecionada = boxUsinas.values.firstWhere((u) => u.id == l.usinaId);
    } catch (_) {}

    _dataReferencia = l.dataReferencia;
    _geracaoController.text = _formatarParaBR(l.geracaoTotalKwh);
    _injetadaController.text = _formatarParaBR(l.energiaInjetadaKwh);
    _consumoController.text = _formatarParaBR(l.energiaConsumidaRedeKwh);
    _valorFaturaController.text = _formatarParaBR(l.valorFaturaR);

    if (l.creditosRecebidosDeTerceiros != null &&
        l.creditosRecebidosDeTerceiros! > 0) {
      _creditosTerceirosController.text = _formatarParaBR(
        l.creditosRecebidosDeTerceiros!,
      );
    }

    _saldoAnteriorIA = l.saldoAnteriorFatura ?? 0.0;

    if ((l.tarifaTeUnica ?? 0) > 0 || (l.tarifaTeForaPonta ?? 0) > 0) {
      _temDadosAvancados = true;
      _grupoTarifario = l.grupoTarifario;
      _modalidadeTarifaria = l.modalidadeTarifaria;
      _teUnica = l.tarifaTeUnica ?? 0;
      _tusdUnica = l.tarifaTusdUnica ?? 0;
      _tePonta = l.tarifaTePonta ?? 0;
      _tusdPonta = l.tarifaTusdPonta ?? 0;
      _teForaPonta = l.tarifaTeForaPonta ?? 0;
      _tusdForaPonta = l.tarifaTusdForaPonta ?? 0;
      _multaReativo = l.multaReativo ?? 0;
      _custoIluminacaoPublica = l.custoIluminacaoPublica ?? 0;
      _demandaIA = l.custoDemandaR;

      _consumoPonta = l.consumoPonta ?? 0;
      _consumoForaPonta = l.consumoForaPonta ?? 0;
      _consumoReservado = l.consumoReservado ?? 0;
      _injetadaPonta = l.injetadaPonta ?? 0;
      _injetadaForaPonta = l.injetadaForaPonta ?? 0;
      _injetadaReservada = l.injetadaReservada ?? 0;

      _custoDemandaController.text = _formatarParaBR(
        l.custoDemandaR + _custoIluminacaoPublica,
      );
    } else {
      _tarifaController.text = NumberFormat.currency(
        locale: 'pt_BR',
        symbol: '',
        decimalDigits: 4,
      ).format(l.tarifaKwh).trim();
      _custoDemandaController.text = _formatarParaBR(l.custoDemandaR);
    }

    if (l.leituraInversor != null && l.leituraInversor! > 0) {
      _leituraAtualController.text = _formatarParaBR(l.leituraInversor!);
      double anterior = l.leituraInversor! - l.geracaoTotalKwh;
      if (anterior > 0) {
        _leituraAnteriorController.text = _formatarParaBR(anterior);
      }
    }

    if (l.saldoInformadoNaFatura != null) {
      _saldoAcumuladoController.text = _formatarParaBR(
        l.saldoInformadoNaFatura!,
      );
    }
  }

  void _confirmarExclusao() async {
    final l = widget.lancamentoParaEditar!;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUid)
        .get();
    final bool isAdminBackend = userDoc.data()?['role'] == 'admin';

    if (!mounted) {
      return;
    }

    if (!isAdminBackend && l.criadoPor != _currentUid) {
      AppFeedback.show(
        context,
        "Apenas o autor ou o Admin podem excluir.",
        isError: true,
      );
      return;
    }

    final box = Hive.box<LancamentoMensal>('lancamentos');
    final outrosDestaUsina = box.values
        .where(
          (x) =>
              x.usinaId == l.usinaId &&
              !x.isDeletado &&
              x.idRemoto != l.idRemoto,
        )
        .toList();

    if (outrosDestaUsina.isNotEmpty) {
      final ultimaData = outrosDestaUsina
          .map((e) => e.dataReferencia)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      if (l.dataReferencia.isBefore(ultimaData)) {
        AppFeedback.show(
          context,
          "Só é permitido excluir o lançamento mais recente.",
          isError: true,
        );
        return;
      }
    }

    if (!isAdminBackend) {
      final diferencaDias = DateTime.now()
          .difference(l.ultimaModificacao ?? DateTime.now())
          .inDays;
      if (diferencaDias > 30) {
        AppFeedback.show(
          context,
          "Lançamentos antigos só podem ser excluídos pelo Admin.",
          isError: true,
        );
        return;
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF5F7FA),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.delete_forever, color: Colors.red),
                    SizedBox(width: 8),
                    Text(
                      'Excluir Lançamento',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'O registro será removido permanentemente de todos os dispositivos após a sincronização.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.blueGrey),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () async {
                    final agora = DateTime.now();
                    l.isDeletado = true;
                    l.ultimaModificacao = agora;
                    l.ultimaSincronizacao = agora;

                    await l.save();
                    await SyncQueueService.enqueue('lancamentos', l.id);

                    await _logger.logAction(
                      "DELETE_ENTRY",
                      "Excluiu ${DateFormat('MM/yyyy').format(l.dataReferencia)}",
                    );

                    if (context.mounted) {
                      Navigator.pop(context);
                      Navigator.pop(context);
                      AppFeedback.show(
                        context,
                        'Lançamento movido para a lixeira.',
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'CONFIRMAR EXCLUSÃO',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'CANCELAR',
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _converterParaDouble(String texto) {
    if (texto.isEmpty) {
      return 0.0;
    }
    String apenasNumeros = texto.replaceAll(RegExp(r'[^\d,]'), '');
    String formatoUS = apenasNumeros.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(formatoUS) ?? 0.0;
  }

  String _formatarParaBR(double valor, {int casas = 2}) {
    final formatador = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: '',
      decimalDigits: casas,
    );
    return formatador.format(valor).trim();
  }

  void _buscarLeituraAnterior() {
    if (_usinaSelecionada == null || _isEditando) {
      return;
    }
    final box = Hive.box<LancamentoMensal>('lancamentos');
    final lancamentos = box.values
        .where(
          (l) =>
              l.usinaId == _usinaSelecionada!.id &&
              l.leituraInversor != null &&
              !l.isDeletado,
        )
        .toList();

    if (lancamentos.isNotEmpty) {
      lancamentos.sort(
        (a, b) => b.leituraInversor!.compareTo(a.leituraInversor!),
      );
      setState(() {
        _leituraAnteriorController.text = _formatarParaBR(
          lancamentos.first.leituraInversor!,
        );
      });
    } else {
      setState(() {
        _leituraAnteriorController.clear();
      });
    }
    _verificarDuplicidade();
  }

  void _calcularGeracao() {
    double anterior = _converterParaDouble(_leituraAnteriorController.text);
    double atual = _converterParaDouble(_leituraAtualController.text);

    if (_leituraAtualController.text.isNotEmpty && atual >= anterior) {
      _geracaoController.text = _formatarParaBR(atual - anterior);
    } else if (_leituraAtualController.text.isEmpty) {
      _geracaoController.text = '';
    }
  }

  void _verificarDuplicidade() {
    if (_usinaSelecionada == null || _isEditando) {
      return;
    }
    final box = Hive.box<LancamentoMensal>('lancamentos');
    final existe = box.values.any(
      (l) =>
          l.usinaId == _usinaSelecionada!.id &&
          l.dataReferencia.month == _dataReferencia.month &&
          l.dataReferencia.year == _dataReferencia.year &&
          !l.isDeletado,
    );
    setState(
      () => _avisoDuplicidade = existe
          ? 'Atenção: Já existe um lançamento neste mês.'
          : null,
    );
  }

  void _salvar() async {
    if (_usinaSelecionada == null) {
      AppFeedback.show(context, 'Selecione uma Usina.', isError: true);
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }

    double tarifa = 0;
    if (!_temDadosAvancados) {
      tarifa = _converterParaDouble(_tarifaController.text);
      if (!_tarifaController.text.contains(',')) {
        tarifa = tarifa / 10000;
      }
    }

    double? saldoInformado;
    if (_saldoAcumuladoController.text.isNotEmpty) {
      saldoInformado = _converterParaDouble(_saldoAcumuladoController.text);
    }

    final boxLancamentos = Hive.box<LancamentoMensal>('lancamentos');
    final DateTime agora = DateTime.now();

    double injetadaTratada = _converterParaDouble(_injetadaController.text);
    double creditosTerceirosTratado = _converterParaDouble(
      _creditosTerceirosController.text,
    );

    if (!_usinaSelecionada!.isGeradora && creditosTerceirosTratado == 0.0) {
      final boxUsinas = Hive.box<Usina>('usinas');
      final maes = boxUsinas.values.where(
        (u) =>
            u.isGeradora &&
            u.beneficiarias.any((b) => b.idUsinaFilha == _usinaSelecionada!.id),
      );

      for (var mae in maes) {
        try {
          final vinculo = mae.beneficiarias.firstWhere(
            (b) => b.idUsinaFilha == _usinaSelecionada!.id,
          );
          final lancMae = boxLancamentos.values.firstWhere(
            (lm) =>
                lm.usinaId == mae.id &&
                lm.dataReferencia.year == _dataReferencia.year &&
                lm.dataReferencia.month == _dataReferencia.month &&
                !lm.isDeletado,
          );
          creditosTerceirosTratado +=
              (lancMae.energiaInjetadaKwh * (vinculo.percentual / 100));
        } catch (_) {}
      }
    }

    if (_isEditando) {
      final l = widget.lancamentoParaEditar!;
      l.usinaId = _usinaSelecionada!.id;
      l.dataReferencia = _dataReferencia;
      l.geracaoTotalKwh = _usinaSelecionada!.isGeradora
          ? _converterParaDouble(_geracaoController.text)
          : 0.0;
      l.leituraInversor = _usinaSelecionada!.isGeradora
          ? _converterParaDouble(_leituraAtualController.text)
          : null;

      l.energiaInjetadaKwh = injetadaTratada;
      l.creditosRecebidosDeTerceiros = creditosTerceirosTratado;

      l.energiaConsumidaRedeKwh = _converterParaDouble(_consumoController.text);
      l.tarifaKwh = tarifa;
      l.valorFaturaR = _converterParaDouble(_valorFaturaController.text);

      if (!_temDadosAvancados) {
        l.custoDemandaR = _converterParaDouble(_custoDemandaController.text);
      } else {
        l.custoDemandaR = _demandaIA;
        l.saldoAnteriorFatura = _saldoAnteriorIA;
      }

      l.saldoInformadoNaFatura = saldoInformado;

      if (_temDadosAvancados) {
        l.grupoTarifario = _grupoTarifario;
        l.modalidadeTarifaria = _modalidadeTarifaria;
        l.consumoPonta = _consumoPonta;
        l.consumoForaPonta = _consumoForaPonta;
        l.consumoReservado = _consumoReservado;
        l.injetadaPonta = _injetadaPonta;
        l.injetadaForaPonta = _injetadaForaPonta;
        l.injetadaReservada = _injetadaReservada;
        l.tarifaTeUnica = _teUnica;
        l.tarifaTusdUnica = _tusdUnica;
        l.tarifaTePonta = _tePonta;
        l.tarifaTusdPonta = _tusdPonta;
        l.tarifaTeForaPonta = _teForaPonta;
        l.tarifaTusdForaPonta = _tusdForaPonta;
        l.custoIluminacaoPublica = _custoIluminacaoPublica;
        l.multaReativo = _multaReativo;
      }

      l.ultimaModificacao = agora;
      l.editadoPor = _currentUid;
      await l.save();
      await SyncQueueService.enqueue('lancamentos', l.id);

      await _logger.logAction(
        "UPDATE_ENTRY",
        "Editou lançamento de ${DateFormat('MM/yyyy').format(_dataReferencia)} (${_usinaSelecionada!.nome})",
      );
    } else {
      final novoLancamento = LancamentoMensal(
        usinaId: _usinaSelecionada!.id,
        dataReferencia: _dataReferencia,
        geracaoTotalKwh: _usinaSelecionada!.isGeradora
            ? _converterParaDouble(_geracaoController.text)
            : 0.0,
        energiaInjetadaKwh: injetadaTratada,
        creditosRecebidosDeTerceiros: creditosTerceirosTratado,
        energiaConsumidaRedeKwh: _converterParaDouble(_consumoController.text),
        tarifaKwh: tarifa,
        valorFaturaR: _converterParaDouble(_valorFaturaController.text),
        custoDemandaR: _temDadosAvancados
            ? _demandaIA
            : _converterParaDouble(_custoDemandaController.text),
        leituraInversor: _usinaSelecionada!.isGeradora
            ? _converterParaDouble(_leituraAtualController.text)
            : null,
        saldoInformadoNaFatura: saldoInformado,
        saldoAnteriorFatura: _temDadosAvancados ? _saldoAnteriorIA : null,
        tenantId: _currentUid,
        criadoPor: _currentUid,
        ultimaModificacao: agora,
        isDeletado: false,
        grupoTarifario: _temDadosAvancados ? _grupoTarifario : null,
        modalidadeTarifaria: _temDadosAvancados ? _modalidadeTarifaria : null,
        consumoPonta: _temDadosAvancados ? _consumoPonta : null,
        consumoForaPonta: _temDadosAvancados ? _consumoForaPonta : null,
        consumoReservado: _temDadosAvancados ? _consumoReservado : null,
        injetadaPonta: _temDadosAvancados ? _injetadaPonta : null,
        injetadaForaPonta: _temDadosAvancados ? _injetadaForaPonta : null,
        injetadaReservada: _temDadosAvancados ? _injetadaReservada : null,
        tarifaTeUnica: _temDadosAvancados ? _teUnica : null,
        tarifaTusdUnica: _temDadosAvancados ? _tusdUnica : null,
        tarifaTePonta: _temDadosAvancados ? _tePonta : null,
        tarifaTusdPonta: _temDadosAvancados ? _tusdPonta : null,
        tarifaTeForaPonta: _temDadosAvancados ? _teForaPonta : null,
        tarifaTusdForaPonta: _temDadosAvancados ? _tusdForaPonta : null,
        custoIluminacaoPublica: _temDadosAvancados
            ? _custoIluminacaoPublica
            : null,
        multaReativo: _temDadosAvancados ? _multaReativo : null,
      );

      await boxLancamentos.add(novoLancamento);
      await SyncQueueService.enqueue('lancamentos', novoLancamento.id);

      await _logger.logAction(
        "CREATE_ENTRY",
        "Cadastrou lançamento de ${DateFormat('MM/yyyy').format(_dataReferencia)} (${_usinaSelecionada!.nome})",
      );
    }

    if (!mounted) {
      return;
    }
    AppFeedback.show(context, 'Dados salvos!');
    if (_manterNaTela && !_isEditando) {
      setState(() {
        _leituraAnteriorController.text = _leituraAtualController.text;
        _leituraAtualController.clear();
        _geracaoController.clear();
        _injetadaController.clear();
        _creditosTerceirosController.clear();
        _consumoController.clear();
        _valorFaturaController.clear();
        _saldoAcumuladoController.clear();

        _temDadosAvancados = false;
        _demandaIA = 0.0;
        _saldoAnteriorIA = 0.0;

        _dataReferencia = DateTime(
          _dataReferencia.year,
          _dataReferencia.month + 1,
          1,
        );
        _verificarDuplicidade();
      });
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _selecionarData(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dataReferencia,
      firstDate: DateTime(2010),
      lastDate: DateTime.now(),
      initialDatePickerMode: DatePickerMode.year,
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null) {
      setState(() {
        _dataReferencia = DateTime(picked.year, picked.month, 1);
        _verificarDuplicidade();
      });
    }
  }

  void _abrirAssistenteTarifa() {
    final custoEnergiaCtrl = TextEditingController();
    final kwhTotalCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF5F7FA),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calculate, color: Colors.deepOrange),
                    SizedBox(width: 8),
                    Text(
                      'Calculadora de Tarifa',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildStylishField(
                  controller: custoEnergiaCtrl,
                  label: 'Valor Total Energia (R\$)',
                  hint: '0,00',
                  icon: Icons.attach_money,
                  isMoeda: true,
                ),
                const SizedBox(height: 12),
                _buildStylishField(
                  controller: kwhTotalCtrl,
                  label: 'Consumo Total (kWh)',
                  hint: '0,00',
                  icon: Icons.bolt,
                  isKwh: true,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    double valor = _converterParaDouble(custoEnergiaCtrl.text);
                    double kwh = _converterParaDouble(kwhTotalCtrl.text);
                    if (valor > 0 && kwh > 0) {
                      setState(
                        () => _tarifaController.text = _formatarParaBR(
                          valor / kwh,
                          casas: 4,
                        ),
                      );
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'APLICAR TARIFA',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPainelAuditoriaIA() {
    final fmtMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final fmtTarifa = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
      decimalDigits: 4,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade200, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.blue.shade700, size: 24),
              const SizedBox(width: 8),
              Text(
                'AUDITORIA TARIFÁRIA (IA)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade800,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Grupo ${_grupoTarifario ?? "-"}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_grupoTarifario == 'B') ...[
            _buildLinhaAuditoria(
              'Tarifa Energia (TE)',
              fmtTarifa.format(_teUnica),
              Icons.bolt,
            ),
            _buildLinhaAuditoria(
              'Tarifa Fio B (TUSD)',
              fmtTarifa.format(_tusdUnica),
              Icons.electrical_services,
            ),
          ] else ...[
            _buildLinhaAuditoria(
              'TE (Ponta / Fora)',
              '${fmtTarifa.format(_tePonta)} / ${fmtTarifa.format(_teForaPonta)}',
              Icons.bolt,
            ),
            _buildLinhaAuditoria(
              'TUSD (Ponta / Fora)',
              '${fmtTarifa.format(_tusdPonta)} / ${fmtTarifa.format(_tusdForaPonta)}',
              Icons.electrical_services,
            ),
          ],

          const Divider(height: 24),
          _buildLinhaAuditoria(
            'Demanda / CIP',
            fmtMoeda.format(_demandaIA + _custoIluminacaoPublica),
            Icons.lightbulb_outline,
          ),

          if (_multaReativo > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: _buildLinhaAuditoria(
                'Multa (Reativo/Excedente)',
                fmtMoeda.format(_multaReativo),
                Icons.warning_amber_rounded,
                corDestaque: Colors.red,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLinhaAuditoria(
    String label,
    String valor,
    IconData icon, {
    Color? corDestaque,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: corDestaque ?? Colors.blueGrey),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: corDestaque ?? Colors.blueGrey.shade700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          Text(
            valor,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: corDestaque ?? Colors.black87,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isWeb = MediaQuery.of(context).size.width >= 900;
    bool isGeradora = _usinaSelecionada?.isGeradora ?? true;

    final boxUsinas = Hive.box<Usina>('usinas');
    final listaUsinas = boxUsinas.values
        .where((u) => u.ativa && !u.isDeletado)
        .toList();

    bool podeExcluir = false;
    if (_isEditando) {
      final l = widget.lancamentoParaEditar!;
      bool isCriador = l.criadoPor == _currentUid;
      podeExcluir = _isAdmin || isCriador;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(
          _isEditando ? 'Editar Lançamento' : 'Novo Lançamento',
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
        automaticallyImplyLeading: !isWeb,
        leading: isWeb
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black87),
                onPressed: () => Navigator.pop(context),
              ),
        actions: [
          if (_isEditando && podeExcluir)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Excluir',
              onPressed: _confirmarExclusao,
            ),
          if (isWeb)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.black87, size: 28),
                tooltip: 'Fechar',
                onPressed: () => Navigator.pop(context),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          children: [
            if (!_isEditando) ...[
              GestureDetector(
                onTap: () async {
                  final dadosExtraidos = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ImportacaoIaScreen(
                        usinaSelecionada: _usinaSelecionada,
                      ),
                    ),
                  );
                  if (dadosExtraidos != null &&
                      dadosExtraidos is Map<String, dynamic>) {
                    _preencherDadosDaIA(dadosExtraidos);
                  }
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2C3E50), Color(0xFF3498DB)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.auto_awesome,
                          color: Colors.amberAccent,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Importação Inteligente',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Envie o PDF e deixe a IA preencher tudo. Clique aqui',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'PRO',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            _buildSectionTitle('Contexto', Icons.place),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blueGrey.withValues(alpha: 0.08),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<Usina>(
                          initialValue: _usinaSelecionada,
                          isExpanded: true,
                          onChanged: _isEditando
                              ? null
                              : (val) {
                                  setState(() {
                                    _usinaSelecionada = val;
                                    _buscarLeituraAnterior();
                                  });
                                },
                          decoration: const InputDecoration(
                            labelText: 'Usina / Instalação',
                            border: InputBorder.none,
                          ),
                          items: listaUsinas
                              .map(
                                (u) => DropdownMenuItem(
                                  value: u,
                                  child: Text(
                                    '${u.nome} (${u.isGeradora ? 'Geradora' : 'Beneficiária'})',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      if (!_isEditando)
                        IconButton(
                          icon: const Icon(
                            Icons.add_circle_outline,
                            color: Colors.deepOrange,
                          ),
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const CadastroUsinaScreen(),
                              ),
                            );
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                  const Divider(),
                  ListTile(
                    onTap: () => _selecionarData(context),
                    leading: const Icon(
                      Icons.calendar_month,
                      color: Colors.deepOrange,
                    ),
                    title: Text(
                      DateFormat(
                        'MMMM yyyy',
                        'pt_BR',
                      ).format(_dataReferencia).toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    trailing: const Text(
                      'Alterar',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_avisoDuplicidade != null) _buildAviso(_avisoDuplicidade!),

            if (isGeradora) ...[
              const SizedBox(height: 30),
              _buildSectionTitle('Leitura do Inversor (E-Total)', Icons.speed),
              _buildLeituraInversorCard(),
            ],

            const SizedBox(height: 30),
            _buildSectionTitle('Dados da Fatura (Conta)', Icons.receipt_long),

            if (_temDadosAvancados)
              _buildPainelAuditoriaIA()
            else ...[
              _buildStylishField(
                controller: _tarifaController,
                label: 'Tarifa (Média)',
                hint: '0,0000',
                icon: Icons.price_check,
                isTarifa: true,
                onCalculatorTap: _abrirAssistenteTarifa,
              ),
              const SizedBox(height: 12),
            ],

            _buildStylishField(
              controller: _injetadaController,
              label: isGeradora
                  ? 'Energia Injetada (Rede)'
                  : 'Geração / Injeção Local (Se houver)',
              hint: '0,00',
              icon: Icons.upload,
              isKwh: true,
              suffix: 'kWh',
            ),
            const SizedBox(height: 12),

            // --- LIBERAÇÃO VISUAL: Mostra o campo de Créditos Recebidos para QUALQUER Usina ---
            _buildStylishField(
              controller: _creditosTerceirosController,
              label: isGeradora
                  ? 'Créditos Recebidos (Ex: Outra Usina)'
                  : 'Créditos Recebidos (Usina Mãe)',
              hint: '0,00',
              icon: Icons.assignment_returned_outlined,
              isKwh: true,
              suffix: 'kWh',
            ),
            const SizedBox(height: 12),

            _buildStylishField(
              controller: _consumoController,
              label: 'Energia Consumida da Rede',
              hint: '0,00',
              icon: Icons.download,
              isKwh: true,
              suffix: 'kWh',
            ),
            const SizedBox(height: 12),

            if (!_temDadosAvancados) ...[
              _buildStylishField(
                controller: _custoDemandaController,
                label: 'Custo de Demanda / Fixos',
                hint: '0,00',
                icon: Icons.domain,
                isMoeda: true,
                suffix: 'R\$',
              ),
              const SizedBox(height: 12),
            ],

            _buildStylishField(
              controller: _valorFaturaController,
              label: 'Valor Total da Fatura (Pago)',
              hint: '0,00',
              icon: Icons.attach_money,
              isMoeda: true,
            ),

            const SizedBox(height: 30),
            _buildSectionTitle(
              'Conciliação de Saldo (Opcional)',
              Icons.account_balance_wallet,
            ),
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 12, right: 4),
              child: Text(
                'Se a sua fatura exibir o saldo acumulado total de créditos atualizado, informe aqui para calibrar a matemática do aplicativo.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blueGrey,
                  height: 1.3,
                ),
              ),
            ),
            _buildStylishField(
              controller: _saldoAcumuladoController,
              label: 'Saldo Acumulado na Fatura',
              hint: '0,00',
              icon: Icons.battery_charging_full_rounded,
              isKwh: true,
              suffix: 'kWh',
            ),

            const SizedBox(height: 20),
            if (!_isEditando)
              Row(
                children: [
                  Checkbox(
                    value: _manterNaTela,
                    onChanged: (v) => setState(() => _manterNaTela = v!),
                  ),
                  const Expanded(child: Text("Manter na tela após salvar")),
                ],
              ),
            const SizedBox(height: 30),

            Row(
              children: [
                if (isWeb) ...[
                  Expanded(
                    flex: 1,
                    child: SizedBox(
                      height: 55,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        child: const Text(
                          'CANCELAR',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                Expanded(flex: isWeb ? 2 : 1, child: _buildBotaoSalvar()),
              ],
            ),

            if (_isEditando && podeExcluir && !isWeb) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _confirmarExclusao,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text(
                  'EXCLUIR LANÇAMENTO',
                  style: TextStyle(color: Colors.red),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildLeituraInversorCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildTimelineInput(
            controller: _leituraAnteriorController,
            label: 'Leitura Inicial (Anterior)',
            icon: Icons.history,
            isFirst: true,
          ),
          Row(
            children: [
              const SizedBox(width: 22),
              Container(height: 24, width: 2, color: Colors.grey.shade300),
            ],
          ),
          _buildTimelineInput(
            controller: _leituraAtualController,
            label: 'Leitura Final (Atual)',
            icon: Icons.speed,
            isFirst: false,
          ),
          const SizedBox(height: 20),
          _buildGeracaoCalculada(),
        ],
      ),
    );
  }

  Widget _buildTimelineInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isFirst,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isFirst ? Colors.grey.shade100 : Colors.blue.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: isFirst ? Colors.grey.shade600 : Colors.blue.shade700,
            size: 20,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  KwhInputFormatter(),
                ],
                decoration: const InputDecoration(
                  hintText: '0,00',
                  suffixText: 'kWh',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGeracaoCalculada() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade400, Colors.deepOrange.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.deepOrange.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GERAÇÃO DESTE MÊS',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                    fontSize: 11,
                    letterSpacing: 1.0,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Automático',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: IgnorePointer(
              ignoring: true,
              child: TextFormField(
                controller: _geracaoController,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  color: Colors.white,
                ),
                decoration: const InputDecoration(
                  hintText: '0,00',
                  hintStyle: TextStyle(color: Colors.white54),
                  suffixText: ' kWh',
                  suffixStyle: TextStyle(color: Colors.white70, fontSize: 16),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBotaoSalvar() {
    return Container(
      height: 55,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.deepOrange.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _salvar,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.deepOrange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: Text(
          _isEditando ? 'ATUALIZAR LANÇAMENTO' : 'SALVAR LANÇAMENTO',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildAviso(String msg) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.red.shade50,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.red.shade200),
    ),
    child: Row(
      children: [
        const Icon(Icons.warning, color: Colors.red),
        const SizedBox(width: 12),
        Expanded(
          child: Text(msg, style: const TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );

  Widget _buildSectionTitle(String t, IconData i) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 12),
    child: Row(
      children: [
        Icon(i, size: 20, color: Colors.blueGrey),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            t.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildStylishField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isMoeda = false,
    bool isKwh = false,
    bool isTarifa = false,
    String? suffix,
    VoidCallback? onCalculatorTap,
  }) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.blueGrey.withValues(alpha: 0.08),
          blurRadius: 15,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        if (isMoeda) CurrencyInputFormatter(),
        if (isKwh) KwhInputFormatter(),
        if (isTarifa) TarifaInputFormatter(),
      ],
      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.grey[600]),
        suffixIcon: onCalculatorTap != null
            ? IconButton(
                icon: const Icon(Icons.calculate, color: Colors.blue),
                onPressed: onCalculatorTap,
              )
            : (suffix != null
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        suffix,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    )
                  : null),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
      ),
    ),
  );

  void _preencherDadosDaIA(Map<String, dynamic> json) {
    try {
      final dadosGerais = json['dadosGerais'] ?? {};
      final energia = json['energiaKwh'] ?? {};
      final consumo = energia['consumo'] ?? {};
      final injetada = energia['injetada'] ?? {};
      final tarifas = json['tarifasReaisPorKwh'] ?? {};
      final custos = json['custosAdicionaisReais'] ?? {};

      setState(() {
        _temDadosAvancados = true;
        _grupoTarifario = dadosGerais['grupoTarifario'];
        _modalidadeTarifaria = dadosGerais['modalidade'];

        _teUnica = (tarifas['teUnica'] as num?)?.toDouble() ?? 0;
        _tusdUnica = (tarifas['tusdUnica'] as num?)?.toDouble() ?? 0;
        _tePonta = (tarifas['tePonta'] as num?)?.toDouble() ?? 0;
        _tusdPonta = (tarifas['tusdPonta'] as num?)?.toDouble() ?? 0;
        _teForaPonta = (tarifas['teForaPonta'] as num?)?.toDouble() ?? 0;
        _tusdForaPonta = (tarifas['tusdForaPonta'] as num?)?.toDouble() ?? 0;

        _custoIluminacaoPublica =
            (custos['iluminacaoPublica'] as num?)?.toDouble() ?? 0;
        _multaReativo = (custos['multaReativo'] as num?)?.toDouble() ?? 0;

        _consumoPonta = (consumo['ponta'] as num?)?.toDouble() ?? 0;
        _consumoForaPonta = (consumo['foraPonta'] as num?)?.toDouble() ?? 0;
        _consumoReservado = (consumo['reservado'] as num?)?.toDouble() ?? 0;

        _injetadaPonta = (injetada['ponta'] as num?)?.toDouble() ?? 0;
        _injetadaForaPonta = (injetada['foraPonta'] as num?)?.toDouble() ?? 0;
        _injetadaReservada = (injetada['reservado'] as num?)?.toDouble() ?? 0;

        String mesRef = dadosGerais['mesReferencia'] ?? '';
        if (mesRef.contains('/')) {
          List<String> parts = mesRef.split('/');
          int mes = int.tryParse(parts[0]) ?? _dataReferencia.month;
          int ano = int.tryParse(parts[1]) ?? _dataReferencia.year;
          if (ano < 100) {
            ano += 2000;
          }
          _dataReferencia = DateTime(ano, mes, 1);
        }

        double valorFatura =
            (dadosGerais['valorTotalFatura'] as num?)?.toDouble() ?? 0.0;
        if (valorFatura > 0) {
          _valorFaturaController.text = _formatarParaBR(valorFatura);
        }

        double totalConsumo =
            ((consumo['unico'] as num?)?.toDouble() ?? 0.0) +
            _consumoPonta +
            _consumoForaPonta +
            _consumoReservado;
        if (totalConsumo > 0) {
          _consumoController.text = _formatarParaBR(totalConsumo);
        }

        double totalInjetada =
            ((injetada['unico'] as num?)?.toDouble() ?? 0.0) +
            _injetadaPonta +
            _injetadaForaPonta +
            _injetadaReservada;
        if (totalInjetada > 0) {
          _injetadaController.text = _formatarParaBR(totalInjetada);
        }

        _demandaIA = (custos['demanda'] as num?)?.toDouble() ?? 0.0;
        if (_demandaIA > 0) {
          _custoDemandaController.text = _formatarParaBR(_demandaIA);
        }

        double saldoAtual =
            (dadosGerais['saldoCreditosAcumuladosKwh'] as num?)?.toDouble() ??
            0.0;
        if (saldoAtual > 0) {
          _saldoAcumuladoController.text = _formatarParaBR(saldoAtual);
        }

        _saldoAnteriorIA =
            (dadosGerais['saldoAnteriorFatura'] as num?)?.toDouble() ?? 0.0;

        if (_usinaSelecionada != null && _saldoAnteriorIA > 0) {
          final boxLanc = Hive.box<LancamentoMensal>('lancamentos');
          final historico = boxLanc.values
              .where((l) => l.usinaId == _usinaSelecionada!.id && !l.isDeletado)
              .toList();

          DateTime mesAnterior = DateTime(
            _dataReferencia.year,
            _dataReferencia.month - 1,
            1,
          );

          try {
            var lancAnterior = historico.firstWhere(
              (l) =>
                  l.dataReferencia.year == mesAnterior.year &&
                  l.dataReferencia.month == mesAnterior.month,
            );

            if (lancAnterior.saldoInformadoNaFatura != null) {
              double diferenca =
                  _saldoAnteriorIA - lancAnterior.saldoInformadoNaFatura!;

              if (diferenca > 2.0) {
                _creditosTerceirosController.text = _formatarParaBR(diferenca);
              }
            }
          } catch (_) {}
        }
      });
    } catch (e) {
      debugPrint("Erro IA: $e");
      AppFeedback.show(context, 'Erro ao preencher dados.', isError: true);
    }
  }
}

class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }
    double value =
        double.parse(newValue.text.replaceAll(RegExp(r'[^\d]'), '')) / 100;
    String newText = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
    ).format(value);
    return newValue.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}

class KwhInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }
    double value =
        double.parse(newValue.text.replaceAll(RegExp(r'[^\d]'), '')) / 100;
    String newText = NumberFormat.decimalPattern('pt_BR').format(value);
    if (!newText.contains(',')) {
      newText += ',00';
    } else if (newText.split(',')[1].length == 1) {
      newText += '0';
    }
    return newValue.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}

class TarifaInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }
    double value =
        double.parse(newValue.text.replaceAll(RegExp(r'[^\d]'), '')) / 10000;
    String newText = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: '',
      decimalDigits: 4,
    ).format(value);
    return newValue.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}
