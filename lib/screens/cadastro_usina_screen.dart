// Caminho: lib/screens/cadastro_usina_screen.dart
// Descrição: Tela de Cadastro com Bloqueios Inteligentes (Freemium) e Regras para Funcionários/Admin.
//
// ALTERAÇÕES DESTA VERSÃO:
//   1. Adição do `_novaUcController` para gerenciar a nova máscara de exibição da concessionária.
//   2. Adição do parâmetro `isObrigatorio` no `_buildStylishField` para permitir campos opcionais.
//   3. O campo "Novo Código UC" fica permanentemente editável, mesmo com o histórico trancado.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:brasil_fields/brasil_fields.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../models/usina.dart';
import '../models/lancamento.dart';
import '../utils/app_feedback.dart';
import '../services/logger_service.dart';
import '../services/sync_queue_service.dart';
import '../services/subscription_provider.dart';
import 'paywall_screen.dart';

class CadastroUsinaScreen extends StatefulWidget {
  final Usina? usinaParaEditar;

  const CadastroUsinaScreen({super.key, this.usinaParaEditar});

  @override
  State<CadastroUsinaScreen> createState() => _CadastroUsinaScreenState();
}

class _CadastroUsinaScreenState extends State<CadastroUsinaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _logger = LoggerService();
  final _numeroFormat = NumberFormat.decimalPattern('pt_BR');

  final _nomeController = TextEditingController();
  final _ucController = TextEditingController();
  // ✅ NOVO: Controlador para o código alternativo da concessionária
  final _novaUcController = TextEditingController();

  // ATUALIZAÇÃO: Neoenergia Coelba adicionada à lista de concessionárias suportadas.
  final List<String> _opcoesConcessionaria = [
    'Santa Maria',
    'EDP',
    'Neoenergia Coelba',
    'Outra',
  ];
  String _concessionaria = 'Santa Maria';
  String _tipoSelecionado = tipoGeradora;

  // Listas de Equipamentos
  List<InversorItem> _listaInversores = [];
  List<PainelItem> _listaPaineis = [];
  List<InvestimentoItem> _listaInvestimentos = [];
  List<BeneficiariaItem> _listaBeneficiarias = [];

  bool _temHistoricoFinanceiro = false;
  bool _isAdmin = false;
  String _currentUid = '';

  // Variáveis para Contagem de Limites
  int _totalGeradorasAtuais = 0;
  int _totalBeneficiariasAtuais = 0;

  double get totalPotenciaInversores {
    if (_listaInversores.isEmpty) return 0.0;
    return _listaInversores.fold(
      0.0,
      (acc, item) => acc + (item.quantidade * item.potenciaKw),
    );
  }

  double get totalPotenciaPaineis {
    if (_listaPaineis.isEmpty) return 0.0;
    return _listaPaineis.fold(
      0.0,
      (acc, item) => acc + (item.quantidade * (item.potenciaWatts / 1000)),
    );
  }

  @override
  void initState() {
    super.initState();
    _carregarPermissoes();
    _contarUsinasAtuais();

    if (widget.usinaParaEditar != null) {
      final usina = widget.usinaParaEditar!;
      _nomeController.text = usina.nome;
      _ucController.text = usina.id;
      // ✅ NOVO: Carrega o dado existente, se houver
      _novaUcController.text = usina.novaUcConcessionaria ?? '';
      _concessionaria = _opcoesConcessionaria.contains(usina.concessionaria)
          ? usina.concessionaria
          : 'Outra';
      _tipoSelecionado = usina.tipo;
      _listaInversores = List.from(usina.inversores);
      _listaPaineis = List.from(usina.paineis);
      _listaInvestimentos = List.from(usina.investimentos);
      _listaBeneficiarias = List.from(usina.beneficiarias);
      _verificarHistorico(usina.id);
    } else {
      // Lógica Inteligente para Novo Cadastro:
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final subProvider = Provider.of<SubscriptionProvider>(
          context,
          listen: false,
        );
        if (!subProvider.podeAdicionarUsinaGeradora(_totalGeradorasAtuais) &&
            subProvider.podeAdicionarUsinaFilha(_totalBeneficiariasAtuais)) {
          setState(() {
            _tipoSelecionado = tipoBeneficiaria;
          });
        }
      });
    }
  }

  void _contarUsinasAtuais() {
    final box = Hive.box<Usina>('usinas');
    setState(() {
      _totalGeradorasAtuais = box.values
          .where((u) => u.isGeradora && !u.isDeletado)
          .length;
      _totalBeneficiariasAtuais = box.values
          .where((u) => !u.isGeradora && !u.isDeletado)
          .length;
    });
  }

  double _parsePotencia(String text) {
    if (text.isEmpty) return 0.0;
    String clean = text.trim().replaceAll(',', '.');
    clean = clean.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(clean) ?? 0.0;
  }

  Future<void> _carregarPermissoes() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _currentUid = user.uid;
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (mounted) {
          setState(() {
            _isAdmin = doc.data()?['role'] == 'admin';
          });
        }
      } catch (e) {
        debugPrint("Erro ao carregar permissões: $e");
      }
    }
  }

  void _verificarHistorico(String usinaId) {
    final boxLancamentos = Hive.box<LancamentoMensal>('lancamentos');
    final tem = boxLancamentos.values.any(
      (l) => l.usinaId == usinaId && !l.isDeletado,
    );
    setState(() => _temHistoricoFinanceiro = tem);
  }

  void _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    final box = Hive.box<Usina>('usinas');
    final user = FirebaseAuth.instance.currentUser;
    final String currentUid = user?.uid ?? 'offline_user';
    final DateTime agora = DateTime.now();

    // Limpa a nova UC se for submetida vazia
    final String? novaUcParsed = _novaUcController.text.trim().isEmpty
        ? null
        : _novaUcController.text.trim();

    if (widget.usinaParaEditar == null) {
      bool existeAtiva = box.values.any(
        (u) => u.id == _ucController.text && u.ativa && !u.isDeletado,
      );
      if (existeAtiva) {
        AppFeedback.show(
          context,
          'Erro: Já existe uma Unidade ATIVA com esta UC.',
          isError: true,
        );
        return;
      }
    }

    if (_tipoSelecionado == tipoGeradora &&
        (_listaInversores.isEmpty || _listaPaineis.isEmpty)) {
      AppFeedback.show(
        context,
        'Erro: Geradora exige Inversores e Painéis.',
        isError: true,
      );
      return;
    }

    if (widget.usinaParaEditar != null) {
      var usina = widget.usinaParaEditar!;
      usina.nome = _nomeController.text;
      usina.id = _ucController.text;
      usina.novaUcConcessionaria = novaUcParsed; // ✅ NOVO: Atualiza o campo
      usina.concessionaria = _concessionaria;
      usina.tipo = _tipoSelecionado;
      usina.inversores = List.from(_listaInversores);
      usina.paineis = List.from(_listaPaineis);
      usina.investimentos = List.from(_listaInvestimentos);
      usina.beneficiarias = List.from(_listaBeneficiarias);
      usina.ultimaSincronizacao = agora;

      await usina.save();
      await SyncQueueService.enqueue('usinas', usina.id);
      await _logger.logAction("UPDATE_PLANT", "Editou a usina ${usina.nome}");
    } else {
      final novaUsina = Usina(
        id: _ucController.text,
        nome: _nomeController.text,
        novaUcConcessionaria: novaUcParsed, // ✅ NOVO: Salva na criação
        concessionaria: _concessionaria,
        tipo: _tipoSelecionado,
        ativa: true,
        inversores: _listaInversores,
        paineis: _listaPaineis,
        investimentos: _listaInvestimentos,
        beneficiarias: _listaBeneficiarias,
        tenantId: currentUid,
        criadoPor: currentUid,
        ultimaSincronizacao: agora,
      );
      await box.add(novaUsina);
      await SyncQueueService.enqueue('usinas', novaUsina.id);
      await _logger.logAction(
        "CREATE_PLANT",
        "Cadastrou a usina ${novaUsina.nome}",
      );
    }

    if (mounted) {
      AppFeedback.show(context, 'Dados salvos com sucesso!');
      Navigator.pop(context);
    }
  }

  void _executarArquivamento() async {
    final usina = widget.usinaParaEditar!;
    final agora = DateTime.now();
    usina.ativa = false;
    usina.ultimaSincronizacao = agora;
    await usina.save();
    await SyncQueueService.enqueue('usinas', usina.id);
    await _logger.logAction("ARCHIVE_PLANT", "Arquivou a usina ${usina.nome}");
    if (mounted) Navigator.pop(context);
  }

  void _executarExclusaoTotal() async {
    final usina = widget.usinaParaEditar!;
    final agora = DateTime.now();
    usina.isDeletado = true;
    usina.ultimaSincronizacao = agora;
    await usina.save();
    await SyncQueueService.enqueue('usinas', usina.id);
    await _logger.logAction("DELETE_PLANT", "Excluiu a usina ${usina.nome}");
    if (mounted) Navigator.pop(context);
  }

  void _gerenciarExclusao() {
    if (widget.usinaParaEditar == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFF5F7FA),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDialogTitle(
              _temHistoricoFinanceiro ? 'Desativar Unidade' : 'Excluir Unidade',
              _temHistoricoFinanceiro ? Icons.archive : Icons.delete_forever,
            ),
            const SizedBox(height: 16),
            Text(
              _temHistoricoFinanceiro
                  ? 'Esta unidade possui histórico financeiro e será arquivada para preservar os dados.'
                  : 'Deseja excluir esta unidade definitivamente? O registro sumirá do App e da Nuvem.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.blueGrey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Fecha o modal
                _temHistoricoFinanceiro
                    ? _executarArquivamento()
                    : _executarExclusaoTotal();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _temHistoricoFinanceiro
                    ? Colors.orange
                    : Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                _temHistoricoFinanceiro
                    ? 'CONFIRMAR ARQUIVAMENTO'
                    : 'CONFIRMAR EXCLUSÃO',
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'CANCELAR',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _vincularBeneficiaria() {
    final subProvider = Provider.of<SubscriptionProvider>(
      context,
      listen: false,
    );

    int totalFilhasAtivas = _listaBeneficiarias
        .where((b) => b.dataFim == null)
        .length;

    if (!subProvider.podeAdicionarUsinaFilha(totalFilhasAtivas)) {
      if (subProvider.isAdmin) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PaywallScreen(
              mensagemMotivo:
                  "Limite de filhas atingido (${SubscriptionProvider.limiteUsinasFilhasGratis} unidades).",
            ),
          ),
        );
      } else {
        AppFeedback.show(
          context,
          "🔒 Limite de rateio atingido. Solicite ao administrador que faça o upgrade para o PRO.",
          isError: true,
        );
      }
      return;
    }

    final percCtrl = TextEditingController();
    DateTime dataSelecionada = DateTime.now();

    final candidatos = Hive.box<Usina>('usinas').values
        .where(
          (u) =>
              u.id != _ucController.text &&
              u.ativa &&
              !u.isDeletado &&
              !_listaBeneficiarias.any(
                (b) => b.idUsinaFilha == u.id && b.dataFim == null,
              ),
        )
        .toList();

    if (candidatos.isEmpty) {
      AppFeedback.show(
        context,
        'Nenhuma outra Unidade ativa disponível.',
        isError: true,
      );
      return;
    }

    Usina? selecionada;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF5F7FA),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDialogTitle('Vincular Unidade', Icons.link),
              const SizedBox(height: 20),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Vigente a partir de: ${DateFormat('dd/MM/yyyy').format(dataSelecionada)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                  ),
                ),
                trailing: const Icon(
                  Icons.calendar_today,
                  color: Colors.deepOrange,
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: dataSelecionada,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                  );
                  if (picked != null) {
                    setModalState(() => dataSelecionada = picked);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Usina>(
                items: candidatos
                    .map(
                      (u) => DropdownMenuItem(
                        value: u,
                        child: Text('${u.nome} (UC ${u.id})'),
                      ),
                    )
                    .toList(),
                onChanged: (val) => selecionada = val,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildStylishField(
                controller: percCtrl,
                label: 'Porcentagem (%)',
                hint: 'Ex: 20',
                icon: Icons.pie_chart,
                isNumber: true,
                suffix: '%',
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  if (selecionada != null && percCtrl.text.isNotEmpty) {
                    setState(
                      () => _listaBeneficiarias.add(
                        BeneficiariaItem(
                          nome: selecionada!.nome,
                          idUsinaFilha: selecionada!.id,
                          percentual: _parsePotencia(percCtrl.text),
                          dataInicio: dataSelecionada,
                        ),
                      ),
                    );
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('VINCULAR'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _alterarPercentual(BeneficiariaItem itemAtivo) {
    final percCtrl = TextEditingController(
      text: itemAtivo.percentual.toString(),
    );
    DateTime dataSelecionada = DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF5F7FA),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDialogTitle(
                'Alterar Rateio: ${itemAtivo.nome}',
                Icons.edit_calendar,
              ),
              const SizedBox(height: 20),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Novo rateio válido a partir de:\n${DateFormat('dd/MM/yyyy').format(dataSelecionada)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                  ),
                ),
                trailing: const Icon(
                  Icons.calendar_today,
                  color: Colors.deepOrange,
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: dataSelecionada,
                    firstDate: itemAtivo.dataInicio,
                    lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                  );
                  if (picked != null) {
                    setModalState(() => dataSelecionada = picked);
                  }
                },
              ),
              const SizedBox(height: 12),
              _buildStylishField(
                controller: percCtrl,
                label: 'Nova Porcentagem (%)',
                hint: 'Ex: 40',
                icon: Icons.pie_chart,
                isNumber: true,
                suffix: '%',
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  if (percCtrl.text.isNotEmpty) {
                    setState(() {
                      itemAtivo.dataFim = dataSelecionada.subtract(
                        const Duration(days: 1),
                      );

                      _listaBeneficiarias.add(
                        BeneficiariaItem(
                          nome: itemAtivo.nome,
                          idUsinaFilha: itemAtivo.idUsinaFilha,
                          percentual: _parsePotencia(percCtrl.text),
                          dataInicio: dataSelecionada,
                        ),
                      );
                    });
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('SALVAR NOVO RATEIO'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addInversor() {
    final marcaCtrl = TextEditingController();
    final potCtrl = TextEditingController();
    final qtdCtrl = TextEditingController(text: '1');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDialogTitle(
              'Adicionar Inversor',
              Icons.settings_input_component,
            ),
            const SizedBox(height: 20),
            _buildStylishField(
              controller: marcaCtrl,
              label: 'Marca/Modelo',
              hint: 'Ex: Growatt 7500',
              icon: Icons.branding_watermark,
            ),
            const SizedBox(height: 12),
            _buildStylishField(
              controller: potCtrl,
              label: 'Potência Unitária (kW)',
              hint: 'Ex: 7.5 ou 7,5',
              icon: Icons.bolt,
              isNumber: true,
            ),
            const SizedBox(height: 12),
            _buildStylishField(
              controller: qtdCtrl,
              label: 'Quantidade',
              hint: '1',
              icon: Icons.numbers,
              isNumber: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                if (marcaCtrl.text.isNotEmpty && potCtrl.text.isNotEmpty) {
                  setState(() {
                    _listaInversores.add(
                      InversorItem(
                        marca: marcaCtrl.text,
                        potenciaKw: _parsePotencia(potCtrl.text),
                        quantidade: int.tryParse(qtdCtrl.text) ?? 1,
                      ),
                    );
                  });
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('ADICIONAR INVERSOR'),
            ),
          ],
        ),
      ),
    );
  }

  void _addPainel() {
    final marcaCtrl = TextEditingController();
    final potCtrl = TextEditingController();
    final qtdCtrl = TextEditingController(text: '1');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDialogTitle('Adicionar Painéis', Icons.grid_view),
            const SizedBox(height: 20),
            _buildStylishField(
              controller: marcaCtrl,
              label: 'Marca',
              hint: 'Ex: Canadian Solar',
              icon: Icons.branding_watermark,
            ),
            const SizedBox(height: 12),
            _buildStylishField(
              controller: potCtrl,
              label: 'Potência Unitária (Watts)',
              hint: '600',
              icon: Icons.bolt,
              isNumber: true,
            ),
            const SizedBox(height: 12),
            _buildStylishField(
              controller: qtdCtrl,
              label: 'Quantidade',
              hint: '20',
              icon: Icons.numbers,
              isNumber: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                if (marcaCtrl.text.isNotEmpty && potCtrl.text.isNotEmpty) {
                  setState(() {
                    _listaPaineis.add(
                      PainelItem(
                        marca: marcaCtrl.text,
                        potenciaWatts: _parsePotencia(potCtrl.text),
                        quantidade: int.tryParse(qtdCtrl.text) ?? 1,
                      ),
                    );
                  });
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('ADICIONAR PAINÉIS'),
            ),
          ],
        ),
      ),
    );
  }

  void _addInvestimento() {
    final descCtrl = TextEditingController();
    final valorCtrl = TextEditingController();
    DateTime dataSelecionada = DateTime.now();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDialogTitle('Novo Custo/Investimento', Icons.attach_money),
              const SizedBox(height: 20),
              ListTile(
                title: Text(
                  'Data: ${DateFormat('dd/MM/yyyy').format(dataSelecionada)}',
                ),
                trailing: const Icon(
                  Icons.calendar_today,
                  color: Colors.deepOrange,
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: dataSelecionada,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setModalState(() => dataSelecionada = picked);
                  }
                },
              ),
              _buildStylishField(
                controller: descCtrl,
                label: 'Descrição',
                hint: 'Ex: Instalação',
                icon: Icons.description,
              ),
              const SizedBox(height: 12),
              _buildStylishField(
                controller: valorCtrl,
                label: 'Valor (R\$)',
                hint: '0,00',
                icon: Icons.monetization_on,
                isMoeda: true,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  if (descCtrl.text.isNotEmpty && valorCtrl.text.isNotEmpty) {
                    setState(
                      () => _listaInvestimentos.add(
                        InvestimentoItem(
                          data: dataSelecionada,
                          descricao: descCtrl.text,
                          valor: UtilBrasilFields.converterMoedaParaDouble(
                            valorCtrl.text,
                          ),
                        ),
                      ),
                    );
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('ADICIONAR CUSTO'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isGeradora = _tipoSelecionado == tipoGeradora;

    double totalRateio = _listaBeneficiarias
        .where((b) => b.dataFim == null)
        .fold(0.0, (acc, item) => acc + item.percentual);

    double sobraGeradora = 100 - totalRateio;
    bool isCriador = widget.usinaParaEditar?.criadoPor == _currentUid;
    bool podeExcluir = _isAdmin || isCriador;

    bool isWeb = MediaQuery.of(context).size.width >= 800;

    final subProvider = Provider.of<SubscriptionProvider>(context);
    bool podeGeradora = subProvider.podeAdicionarUsinaGeradora(
      _totalGeradorasAtuais,
    );
    bool podeBeneficiaria = subProvider.podeAdicionarUsinaFilha(
      _totalBeneficiariasAtuais,
    );

    if (widget.usinaParaEditar != null) {
      if (widget.usinaParaEditar!.isGeradora) podeGeradora = true;
      if (!widget.usinaParaEditar!.isGeradora) podeBeneficiaria = true;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(
          widget.usinaParaEditar != null ? 'Editar Unidade' : 'Nova Unidade',
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        automaticallyImplyLeading: !isWeb,
        leading: isWeb
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black87),
                onPressed: () => Navigator.pop(context),
              ),
        actions: [
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
            IgnorePointer(
              ignoring: _temHistoricoFinanceiro,
              child: Opacity(
                opacity: _temHistoricoFinanceiro ? 0.6 : 1.0,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      _buildTypeOption(
                        'GERADORA',
                        tipoGeradora,
                        Icons.solar_power,
                        isBloqueado: !podeGeradora,
                        isAdmin: subProvider.isAdmin,
                      ),
                      _buildTypeOption(
                        'BENEFICIÁRIA',
                        tipoBeneficiaria,
                        Icons.home_work,
                        isBloqueado: !podeBeneficiaria,
                        isAdmin: subProvider.isAdmin,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_temHistoricoFinanceiro) _buildLockAviso(),
            _buildSectionTitle('Identificação', Icons.badge_outlined),
            _buildStylishField(
              controller: _nomeController,
              label: 'Apelido (Nome)',
              hint: 'Ex: Casa de Praia',
              icon: Icons.edit_outlined,
              isReadOnly: _temHistoricoFinanceiro,
            ),
            const SizedBox(height: 16),
            _buildConcessionariaDropdown(),
            const SizedBox(height: 16),
            _buildStylishField(
              controller: _ucController,
              label: 'Nº da UC Original (Código)',
              hint: 'Número da instalação na primeira fatura',
              icon: Icons.numbers,
              isNumber: true,
              isReadOnly: _temHistoricoFinanceiro,
            ),

            // ✅ NOVO CAMPO: Opcional e permanentemente livre
            _buildStylishField(
              controller: _novaUcController,
              label: 'Novo Código UC (Opcional)',
              hint: 'Apenas se a concessionária mudou o código original',
              icon: Icons.pin_outlined,
              isNumber: true,
              isReadOnly: false,
              isObrigatorio: false, // Não tranca o formulário
            ),

            if (isGeradora) ...[
              _buildRateioSection(totalRateio, sobraGeradora),
              _buildListaInversoresDetalhada(),
              _buildListaPaineisDetalhada(),
              const SizedBox(height: 16),
              _buildResumoCalculadora(),
              _buildComponentSection(
                'Investimento',
                Icons.attach_money,
                _listaInvestimentos,
                _addInvestimento,
              ),
            ],

            const SizedBox(height: 40),

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
                Expanded(flex: isWeb ? 2 : 1, child: _buildBotaoPrincipal()),
              ],
            ),

            if (widget.usinaParaEditar != null && podeExcluir)
              _buildBotaoExcluir(),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // --- WIDGETS AUXILIARES DA CALCULADORA ---
  Widget _buildResumoCalculadora() {
    double inv = totalPotenciaInversores;
    double painel = totalPotenciaPaineis;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.blueGrey.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Capacidade Instalada:",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                ),
              ),
              Text(
                "${_numeroFormat.format(inv)} kW",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Potência (Painéis):",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                ),
              ),
              Text(
                "${_numeroFormat.format(painel)} kWp",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          if (inv > 0 && painel > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: painel > inv
                      ? Colors.orange.withValues(alpha: 0.1)
                      : Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      painel > inv ? Icons.warning_amber : Icons.check_circle,
                      size: 16,
                      color: painel > inv ? Colors.orange : Colors.green,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        painel > inv
                            ? "Overload: ${((painel / inv) * 100).toStringAsFixed(0)}% (Painéis > Inversor)"
                            : "Sistema Folgado",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[800],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildListaInversoresDetalhada() {
    return Column(
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionTitle('Inversores', Icons.settings_input_component),
            IconButton(
              onPressed: _addInversor,
              icon: const Icon(
                Icons.add_circle,
                color: Colors.deepOrange,
                size: 32,
              ),
            ),
          ],
        ),
        if (_listaInversores.isEmpty)
          const Text(
            "Nenhum inversor adicionado.",
            style: TextStyle(color: Colors.grey),
          ),
        ..._listaInversores.map(
          (item) => Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              title: Text(
                "${item.quantidade}x ${item.marca}",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text("Unit: ${item.potenciaKw} kW"),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "= ${_numeroFormat.format(item.quantidade * item.potenciaKw)} kW",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () =>
                        setState(() => _listaInversores.remove(item)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListaPaineisDetalhada() {
    return Column(
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionTitle('Painéis Solares', Icons.grid_view),
            IconButton(
              onPressed: _addPainel,
              icon: const Icon(
                Icons.add_circle,
                color: Colors.deepOrange,
                size: 32,
              ),
            ),
          ],
        ),
        if (_listaPaineis.isEmpty)
          const Text(
            "Nenhum painel adicionado.",
            style: TextStyle(color: Colors.grey),
          ),
        ..._listaPaineis.map((item) {
          double totalKwLinha = (item.quantidade * item.potenciaWatts) / 1000;
          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              title: Text(
                "${item.quantidade}x ${item.marca}",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text("Unit: ${item.potenciaWatts} W"),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "= ${_numeroFormat.format(totalKwLinha)} kWp",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => setState(() => _listaPaineis.remove(item)),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildLockAviso() => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.orange.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
    ),
    child: const Row(
      children: [
        Icon(Icons.lock, size: 16, color: Colors.orange),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Histórico protegido: Código Original (UC) e o Tipo estão bloqueados.',
            style: TextStyle(color: Colors.brown, fontSize: 12),
          ),
        ),
      ],
    ),
  );

  Widget _buildConcessionariaDropdown() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    decoration: BoxDecoration(
      color: _temHistoricoFinanceiro ? Colors.grey[100] : Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.blueGrey.withValues(alpha: 0.08),
          blurRadius: 15,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: DropdownButtonFormField<String>(
      initialValue: _concessionaria,
      items: _opcoesConcessionaria
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: _temHistoricoFinanceiro
          ? null
          : (val) => setState(() => _concessionaria = val!),
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.electrical_services, color: Colors.grey),
        border: InputBorder.none,
        labelText: 'Concessionária',
      ),
    ),
  );

  Widget _buildRateioSection(double total, double sobra) => Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildSectionTitle('Rateio (Créditos)', Icons.share),
          IconButton(
            onPressed: _vincularBeneficiaria,
            icon: const Icon(Icons.add_link, color: Colors.blue, size: 32),
          ),
        ],
      ),
      if (_listaBeneficiarias.isNotEmpty)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              LinearProgressIndicator(
                value: total / 100,
                backgroundColor: Colors.deepOrange,
                color: Colors.blue,
                minHeight: 8,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Distribuído: ${total.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  Text(
                    'Geradora: ${sobra.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.deepOrange,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ..._listaBeneficiarias
          .where((b) => b.dataFim == null)
          .map(
            (i) => ListTile(
              title: Text(
                i.nome,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Rateio atual: ${i.percentual}%\nDesde: ${DateFormat('dd/MM/yyyy').format(i.dataInicio)}',
              ),
              isThreeLine: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_calendar, color: Colors.blue),
                    tooltip: 'Alterar Porcentagem/Data',
                    onPressed: () => _alterarPercentual(i),
                  ),
                  IconButton(
                    icon: const Icon(Icons.link_off, color: Colors.red),
                    tooltip: 'Remover Vínculo',
                    onPressed: () => setState(() {
                      _listaBeneficiarias.removeWhere(
                        (b) => b.idUsinaFilha == i.idUsinaFilha,
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
    ],
  );

  Widget _buildComponentSection(
    String title,
    IconData icon,
    List list,
    VoidCallback onAdd,
  ) => Column(
    children: [
      const SizedBox(height: 20),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildSectionTitle(title, icon),
          IconButton(
            onPressed: onAdd,
            icon: const Icon(
              Icons.add_circle,
              color: Colors.deepOrange,
              size: 32,
            ),
          ),
        ],
      ),
      ...list.map(
        (item) => Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            title: Text(item.descricao),
            subtitle: Text(UtilBrasilFields.obterReal(item.valor)),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => setState(() => list.remove(item)),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _buildBotaoPrincipal() => Container(
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
      child: Text(
        widget.usinaParaEditar != null
            ? 'SALVAR ALTERAÇÕES'
            : 'CADASTRAR UNIDADE',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    ),
  );

  Widget _buildBotaoExcluir() => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Container(
      height: 55,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _temHistoricoFinanceiro ? Colors.orange : Colors.red,
        ),
        color: (_temHistoricoFinanceiro ? Colors.orange : Colors.red)
            .withValues(alpha: 0.05),
      ),
      child: TextButton(
        onPressed: _gerenciarExclusao,
        child: Text(
          _temHistoricoFinanceiro
              ? 'DESATIVAR / ARQUIVAR'
              : 'EXCLUIR DEFINITIVAMENTE',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.red,
          ),
        ),
      ),
    ),
  );

  Widget _buildTypeOption(
    String label,
    String value,
    IconData icon, {
    bool isBloqueado = false,
    bool isAdmin = true,
  }) {
    bool isSelected = _tipoSelecionado == value;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (isBloqueado) {
            if (isAdmin) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PaywallScreen(
                    mensagemMotivo:
                        "Limite atingido para $label no Plano Grátis.",
                  ),
                ),
              );
            } else {
              AppFeedback.show(
                context,
                "🔒 Limite de $label atingido. Solicite ao administrador que faça o upgrade para o PRO.",
                isError: true,
              );
            }
            return;
          }
          setState(() => _tipoSelecionado = value);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.deepOrange
                : (isBloqueado ? Colors.grey.shade200 : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: isBloqueado
                ? Border.all(color: Colors.grey.shade300)
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isBloqueado ? Icons.lock : icon,
                color: isSelected
                    ? Colors.white
                    : (isBloqueado ? Colors.grey.shade400 : Colors.grey),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : (isBloqueado ? Colors.grey.shade500 : Colors.grey),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDialogTitle(String title, IconData icon) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(icon, color: Colors.deepOrange),
      const SizedBox(width: 8),
      Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
    ],
  );

  Widget _buildSectionTitle(String title, IconData icon) => Row(
    children: [
      Icon(icon, size: 20, color: Colors.blueGrey),
      const SizedBox(width: 8),
      Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.blueGrey,
          letterSpacing: 1.2,
        ),
      ),
    ],
  );

  // ✅ NOVO: Parâmetro isObrigatorio adicionado (padrão true para não afetar os outros campos)
  Widget _buildStylishField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isNumber = false,
    bool isMoeda = false,
    String? suffix,
    bool isReadOnly = false,
    bool isObrigatorio = true,
  }) => Container(
    margin: const EdgeInsets.only(top: 12),
    decoration: BoxDecoration(
      color: isReadOnly ? Colors.grey[100] : Colors.white,
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
      readOnly: isReadOnly,
      validator: isObrigatorio
          ? (v) => (v == null || v.isEmpty) ? 'Campo obrigatório' : null
          : null,
      keyboardType: isNumber
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: isMoeda
          ? [
              FilteringTextInputFormatter.digitsOnly,
              RealInputFormatter(moeda: true),
            ]
          : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: suffix,
        prefixIcon: Icon(icon, color: Colors.grey[600]),
        suffixIcon: isReadOnly
            ? const Icon(Icons.lock, color: Colors.orange)
            : null,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
      ),
    ),
  );
}
