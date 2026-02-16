// Caminho: lib/screens/configuracao_dados_screen.dart
// Descrição: Tela de Gestão de Dados otimizada com exclusão segura, fila de sync e trava de texto.

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/lancamento.dart';
import '../models/usina.dart';
import '../utils/app_feedback.dart';
import '../services/data_backup_service.dart';
import '../services/logger_service.dart';
import '../services/sync_queue_service.dart'; // <-- Import da Fila adicionado

class ConfiguracaoDadosScreen extends StatefulWidget {
  const ConfiguracaoDadosScreen({super.key});

  @override
  State<ConfiguracaoDadosScreen> createState() =>
      _ConfiguracaoDadosScreenState();
}

class _ConfiguracaoDadosScreenState extends State<ConfiguracaoDadosScreen> {
  bool _isLoading = false;
  final _logger = LoggerService();

  // ===========================================================================
  // --- AÇÕES DE EXPORTAÇÃO (SALVAR) ---
  // ===========================================================================

  Future<void> _exportarBackupJson() async {
    String? nome = await _pedirNomeArquivoSheet(
      titulo: 'Salvar Backup JSON',
      padrao: 'backup_solar_${DateFormat('yyyyMMdd').format(DateTime.now())}',
      icone: Icons.save_alt,
    );
    if (nome == null) return;

    setState(() => _isLoading = true);
    try {
      await DataBackupService.exportarBackupJson(nome);
      await _logger.logAction(
        "EXPORT_JSON",
        "Exportou backup completo: $nome.json",
      );
      if (mounted) AppFeedback.show(context, 'Backup salvo com sucesso!');
    } catch (e) {
      if (mounted) AppFeedback.show(context, 'Erro: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _exportarEstruturaUsinas() async {
    String? nome = await _pedirNomeArquivoSheet(
      titulo: 'Exportar Estrutura (Usinas)',
      padrao:
          'estrutura_usinas_${DateFormat('yyyyMMdd').format(DateTime.now())}',
      icone: Icons.account_tree_outlined,
    );
    if (nome == null) return;

    setState(() => _isLoading = true);
    try {
      await DataBackupService.exportarEstruturaUsinas(nome);
      await _logger.logAction(
        "EXPORT_CSV",
        "Exportou estrutura de usinas: $nome.csv",
      );
      if (mounted) AppFeedback.show(context, 'Estrutura salva com sucesso!');
    } catch (e) {
      if (mounted) AppFeedback.show(context, 'Erro: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _exportarRelatorioCsv() async {
    String? nome = await _pedirNomeArquivoSheet(
      titulo: 'Exportar Relatório CSV',
      padrao:
          'relatorio_solar_${DateFormat('yyyyMMdd').format(DateTime.now())}',
      icone: Icons.table_view,
    );
    if (nome == null) return;

    setState(() => _isLoading = true);
    try {
      await DataBackupService.exportarRelatorioCsv(nome);
      await _logger.logAction("EXPORT_CSV", "Gerou relatório CSV: $nome.csv");
      if (mounted) AppFeedback.show(context, 'Relatório salvo com sucesso!');
    } catch (e) {
      if (mounted) AppFeedback.show(context, 'Erro: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ===========================================================================
  // --- AÇÕES DE IMPORTAÇÃO (LER) ---
  // ===========================================================================

  Future<void> _importarEstruturaUsinas() async {
    setState(() => _isLoading = true);
    try {
      String resultado = await DataBackupService.importarEstruturaUsinas();
      if (resultado != "Cancelado") {
        await _logger.logAction(
          "IMPORT_CSV",
          "Importou estrutura de usinas via CSV.",
        );
        if (mounted) AppFeedback.show(context, resultado);
      }
    } catch (e) {
      if (mounted) AppFeedback.show(context, 'Erro: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _importarCsvMassa() async {
    setState(() => _isLoading = true);
    try {
      String resultado = await DataBackupService.importarCsvEmMassa();
      if (resultado != "Cancelado") {
        await _logger.logAction("IMPORT_CSV", "Importou faturas via CSV.");
        if (mounted) AppFeedback.show(context, resultado);
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.show(context, 'Erro na importação: $e', isError: true);
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _restaurarBackupJson() async {
    bool confirmar = await _confirmarAcaoDestrutivaSheet(
      titulo: 'Restaurar Backup?',
      mensagem:
          'ATENÇÃO: Isso APAGARÁ todos os dados atuais e substituirá pelo conteúdo do backup.',
      botaoTexto: 'SIM, RESTAURAR',
      requerDigitacao: true, // Proteção extra!
    );
    if (!confirmar) return;

    setState(() => _isLoading = true);
    try {
      String resultado = await DataBackupService.restaurarBackupJson();
      if (resultado != "Cancelado") {
        await _logger.logAction(
          "RESTORE_JSON",
          "Restaurou o banco de dados via arquivo JSON.",
        );
        if (mounted) AppFeedback.show(context, resultado);
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.show(context, 'Erro ao restaurar: $e', isError: true);
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ===========================================================================
  // --- ZONA DE PERIGO (LIMPEZA TOTAL E LOGS) ---
  // ===========================================================================

  Future<void> _limparBancoDeDados() async {
    bool confirmar = await _confirmarAcaoDestrutivaSheet(
      titulo: 'Apagar TUDO?',
      mensagem:
          'Isso apagará todas as usinas, faturas e o histórico de auditoria (logs) da empresa permanentemente.',
      botaoTexto: 'SIM, APAGAR TUDO',
      requerDigitacao: true, // Proteção obriga a digitar APAGAR
    );
    if (!confirmar) return;

    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("Usuário não autenticado");

      // 1. Descobrir a qual empresa esse Admin pertence
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final String empresaId = userDoc.data()?['empresaId'] ?? user.uid;

      final boxLanc = Hive.box<LancamentoMensal>('lancamentos');
      final boxUsinas = Hive.box<Usina>('usinas');
      final agora = DateTime.now();

      // 2. Soft Delete de Lançamentos + Fila de Sincronização
      final lancKeys = boxLanc.keys.toList();
      for (var key in lancKeys) {
        final l = boxLanc.get(key);
        if (l != null && !l.isDeletado) {
          l.isDeletado = true;
          l.ultimaModificacao = agora;
          await l.save(); // Salva no Hive
          await SyncQueueService.enqueue('lancamentos', l.id); // Avisa a Nuvem
        }
      }

      // 3. Soft Delete de Usinas + Fila de Sincronização
      final usinaKeys = boxUsinas.keys.toList();
      for (var key in usinaKeys) {
        final u = boxUsinas.get(key);
        if (u != null && !u.isDeletado) {
          u.isDeletado = true;
          u.ultimaSincronizacao = agora;
          await u.save(); // Salva no Hive
          await SyncQueueService.enqueue('usinas', u.id); // Avisa a Nuvem
        }
      }

      // 4. Limpeza FÍSICA dos Logs de Auditoria (Exclusivo do Admin)
      final logsSnapshot = await FirebaseFirestore.instance
          .collection('activity_logs')
          .where('empresaId', isEqualTo: empresaId)
          .get();

      for (var doc in logsSnapshot.docs) {
        await doc.reference.delete();
      }

      // 5. Registra o ÚNICO log sobrevivente: O aviso de quem deletou tudo
      await _logger.logAction(
        "DATABASE_WIPE",
        "O Administrador zerou o banco de dados e o histórico de auditoria.",
      );

      if (mounted) {
        AppFeedback.show(
          context,
          'Tudo apagado com sucesso! Clique em Sincronizar para esvaziar a nuvem.',
        );
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.show(context, 'Erro ao limpar: $e', isError: true);
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ===========================================================================
  // --- UI BUILD ---
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'Gestão de Dados',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // --- SEÇÃO JSON ---
                const Text(
                  "Backup de Segurança (JSON)",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 12),
                _buildActionCard(
                  icon: Icons.save_alt,
                  color: Colors.blue,
                  title: "Salvar Backup Completo",
                  subtitle:
                      "Gera arquivo .json com todos os detalhes técnicos.",
                  onTap: _exportarBackupJson,
                ),
                const SizedBox(height: 10),
                _buildActionCard(
                  icon: Icons.restore_page,
                  color: Colors.green,
                  title: "Restaurar Backup",
                  subtitle: "Recupera usinas e faturas de um arquivo .json.",
                  onTap: _restaurarBackupJson,
                ),

                const SizedBox(height: 30),

                // --- SEÇÃO CSV PASSO 1 ---
                const Text(
                  "Passo 1: Exporte e importe suas UCS (CSV)",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 12),
                _buildActionCard(
                  icon: Icons.account_tree_outlined,
                  color: Colors.teal,
                  title: "Importar UCS",
                  subtitle:
                      "Cadastra Unidades Consumidoras/Geradoras em massa.",
                  onTap: _importarEstruturaUsinas,
                ),
                const SizedBox(height: 10),
                _buildActionCard(
                  icon: Icons.file_download_outlined,
                  color: Colors.teal.shade700,
                  title: "Exportar UCS",
                  subtitle: "Gera modelo Excel com as UCs cadastradas.",
                  onTap: _exportarEstruturaUsinas,
                ),

                const SizedBox(height: 30),

                // --- SEÇÃO CSV PASSO 2 ---
                const Text(
                  "Passo 2: Histórico de Faturas (CSV)",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 12),
                _buildActionCard(
                  icon: Icons.history_edu_outlined,
                  color: Colors.deepOrange,
                  title: "Importar Faturas",
                  subtitle: "Vincula dados de geração e consumo às UCS.",
                  onTap: _importarCsvMassa,
                ),
                const SizedBox(height: 10),
                _buildActionCard(
                  icon: Icons.table_view,
                  color: Colors.orange,
                  title: "Exportar faturas",
                  subtitle: "Exporta auditoria completa para análise externa.",
                  onTap: _exportarRelatorioCsv,
                ),

                const SizedBox(height: 30),

                // --- ZONA DE PERIGO ---
                const Text(
                  "Zona de Perigo",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 12),
                _buildDangerZoneCard(),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _buildDangerZoneCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: ListTile(
        leading: const Icon(Icons.delete_forever, color: Colors.red),
        title: const Text(
          "Limpar Banco de Dados",
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        subtitle: const Text("Zera os dados e a auditoria de toda a equipe."),
        onTap: _limparBancoDeDados,
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _pedirNomeArquivoSheet({
    required String titulo,
    required String padrao,
    required IconData icone,
  }) async {
    final controller = TextEditingController(text: padrao);
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: "Nome do Arquivo",
                  prefixIcon: Icon(icone),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, controller.text),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("CONFIRMAR"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // MODIFICADO: Agora suporta a exigência de digitar "APAGAR" para ações críticas
  Future<bool> _confirmarAcaoDestrutivaSheet({
    required String titulo,
    required String mensagem,
    required String botaoTexto,
    bool requerDigitacao = false,
  }) async {
    String textoConfirmacao = "";

    return await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => StatefulBuilder(
            builder: (BuildContext context, StateSetter setModalState) {
              // Verifica se o botão pode ser habilitado
              bool podeConfirmar = requerDigitacao
                  ? textoConfirmacao == "APAGAR"
                  : true;

              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 48,
                        color: Colors.red,
                      ),
                      Text(
                        titulo,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        mensagem,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 24),

                      // Mostra o TextField apenas se for uma ação muito perigosa
                      if (requerDigitacao) ...[
                        const Text(
                          "Digite APAGAR para confirmar:",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.redAccent,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          onChanged: (val) {
                            setModalState(() {
                              textoConfirmacao = val.trim().toUpperCase();
                            });
                          },
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            hintText: "APAGAR",
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          // Desabilita o botão se a palavra não for digitada
                          onPressed: podeConfirmar
                              ? () => Navigator.pop(ctx, true)
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.red.shade200,
                          ),
                          child: Text(botaoTexto),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text(
                          "Cancelar",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ) ??
        false;
  }
}
