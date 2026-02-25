// Caminho: lib/screens/auditoria_screen.dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../models/usina.dart';
import '../models/lancamento.dart';
import '../utils/calculadora_energetica.dart';
import '../services/sincronizacao_service.dart'; // <-- IMPORT ADICIONADO PARA O PULL-TO-REFRESH
import '../utils/app_feedback.dart'; // <-- IMPORT DO PADRÃO DE FEEDBACK ADICIONADO
import 'auditoria_individual_screen.dart';
import 'tabs/auditoria_global_tab.dart';

class AuditoriaScreen extends StatefulWidget {
  const AuditoriaScreen({super.key});

  @override
  State<AuditoriaScreen> createState() => _AuditoriaScreenState();
}

class _AuditoriaScreenState extends State<AuditoriaScreen> {
  // A "mágica" para a Web: Um navegador aninhado para a Aba de Unidades
  final GlobalKey<NavigatorState> _nestedNavKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Auditoria & Performance',
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
          bottom: const TabBar(
            labelColor: Colors.deepOrange,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.deepOrange,
            tabs: [
              Tab(text: 'Por Unidade'),
              Tab(text: 'Análise Global'),
            ],
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            bool isWeb = constraints.maxWidth >= 900;

            return TabBarView(
              children: [
                // ABA 1: LISTA POR UNIDADE (Com Navegador Inteligente)
                isWeb
                    ? Navigator(
                        key: _nestedNavKey,
                        onGenerateRoute: (settings) {
                          return MaterialPageRoute(
                            builder: (context) => _AuditoriaListaTab(
                              onTapUsina: (usina) {
                                // Na Web, usamos o navegador aninhado!
                                _nestedNavKey.currentState!.push(
                                  PageRouteBuilder(
                                    pageBuilder:
                                        (
                                          context,
                                          animation,
                                          secondaryAnimation,
                                        ) => AuditoriaIndividualScreen(
                                          usina: usina,
                                        ),
                                    transitionsBuilder:
                                        (
                                          context,
                                          animation,
                                          secondaryAnimation,
                                          child,
                                        ) {
                                          return FadeTransition(
                                            opacity: animation,
                                            child: child,
                                          );
                                        },
                                  ),
                                );
                              },
                              isWeb: true,
                            ),
                          );
                        },
                      )
                    : _AuditoriaListaTab(
                        onTapUsina: (usina) {
                          // No Mobile, usa o Navigator normal para sobrepor o ecrã
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  AuditoriaIndividualScreen(usina: usina),
                            ),
                          );
                        },
                        isWeb: false,
                      ),

                // ABA 2: ANÁLISE GLOBAL (Intocada)
                const AuditoriaGlobalTab(),
              ],
            );
          },
        ),
      ),
    );
  }
}

// --- ABA 1: LISTA POR UNIDADE (Agora recebe o método de navegação) ---
class _AuditoriaListaTab extends StatelessWidget {
  final Function(Usina) onTapUsina;
  final bool isWeb;

  const _AuditoriaListaTab({required this.onTapUsina, required this.isWeb});

  // --- NOVA LÓGICA DE PULL-TO-REFRESH COM FEEDBACK PADRONIZADO ---
  Future<void> _handleRefresh(BuildContext context) async {
    try {
      final resultado = await SincronizacaoService().sincronizarTudo();

      if (!context.mounted) return;

      if (resultado.contains('Erro') ||
          resultado.contains('Sem internet') ||
          resultado.contains('offline')) {
        AppFeedback.show(context, resultado, isError: true);
      } else if (resultado == 'Sincronizado.') {
        AppFeedback.show(context, "Tudo já está sincronizado.", isError: false);
      } else {
        AppFeedback.show(
          context,
          "Dados sincronizados com sucesso!",
          isError: false,
        );
      }
    } catch (e) {
      if (context.mounted) {
        AppFeedback.show(context, "Erro ao atualizar: $e", isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final numero = NumberFormat.decimalPattern('pt_BR');

    return ValueListenableBuilder(
      valueListenable: Hive.box<LancamentoMensal>('lancamentos').listenable(),
      builder: (context, Box<LancamentoMensal> boxLancamentos, _) {
        final boxUsinas = Hive.box<Usina>('usinas');

        // Filtramos apenas usinas que NÃO estão marcadas para deletar e estão ativas
        final usinas = boxUsinas.values
            .where((u) => u.ativa && !u.isDeletado)
            .toList();

        if (usinas.isEmpty) {
          return const Center(child: Text('Nenhuma usina encontrada.'));
        }

        if (isWeb) {
          // ===============================================================
          // LAYOUT WEB: BENTO GRID DE CARDS COM PULL-TO-REFRESH
          // ===============================================================
          return RefreshIndicator(
            color: Colors.deepOrange,
            backgroundColor: Colors.white,
            onRefresh: () => _handleRefresh(context),
            child: GridView.builder(
              padding: const EdgeInsets.all(32),
              physics:
                  const AlwaysScrollableScrollPhysics(), // Garante que o refresh funcione mesmo com a tela vazia
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 400, // Tamanho máximo de cada card
                childAspectRatio: 2.5, // Proporção do card
                crossAxisSpacing: 24,
                mainAxisSpacing: 24,
              ),
              itemCount: usinas.length,
              itemBuilder: (context, index) {
                final usina = usinas[index];
                final lancamentosUsina = boxLancamentos.values
                    .where((l) => l.usinaId == usina.id && !l.isDeletado)
                    .toList();
                final metricas = CalculadoraEnergetica.calcularMetricasGerais(
                  usina,
                  lancamentosUsina,
                );

                return _buildWebCard(context, usina, metricas, moeda, numero);
              },
            ),
          );
        } else {
          // ===============================================================
          // LAYOUT MOBILE: MANTIDO COM PULL-TO-REFRESH ADICIONADO
          // ===============================================================
          return RefreshIndicator(
            color: Colors.deepOrange,
            backgroundColor: Colors.white,
            onRefresh: () => _handleRefresh(context),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              physics:
                  const AlwaysScrollableScrollPhysics(), // Garante que o refresh funcione mesmo com a tela vazia
              itemCount: usinas.length,
              itemBuilder: (context, index) {
                final usina = usinas[index];
                final lancamentosUsina = boxLancamentos.values
                    .where((l) => l.usinaId == usina.id && !l.isDeletado)
                    .toList();
                final metricas = CalculadoraEnergetica.calcularMetricasGerais(
                  usina,
                  lancamentosUsina,
                );

                return Card(
                  elevation: 3, // 1. Tira a sombra pesada
                  color: Colors.white, // 2. Força o fundo branco
                  surfaceTintColor: Colors
                      .transparent, // 3. Desliga o tom rosado do Material 3
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: Colors.grey.shade200,
                    ), // 4. Adiciona borda moderna
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: usina.isGeradora
                          ? Colors.orange.withValues(alpha: 0.1)
                          : Colors.blue.withValues(alpha: 0.1),
                      child: Icon(
                        usina.isGeradora ? Icons.wb_sunny : Icons.home_work,
                        color: usina.isGeradora ? Colors.orange : Colors.blue,
                      ),
                    ),
                    title: Text(
                      usina.nome,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      usina.isGeradora
                          ? 'Gerou: ${numero.format(metricas.totalGeradoKwh)} kWh'
                          : 'Recebeu: ${numero.format(metricas.totalInjetadoKwh)} kWh',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          moeda.format(metricas.valorTotalEconomizadoR),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                            fontSize: 14,
                          ),
                        ),
                        const Text(
                          'Economia',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                    onTap: () => onTapUsina(
                      usina,
                    ), // CHAMA A LÓGICA DE NAVEGAÇÃO EXTERNA
                  ),
                );
              },
            ),
          );
        }
      },
    );
  }

  // WIDGET EXCLUSIVO WEB (Card mais espaçoso para tela grande)
  Widget _buildWebCard(
    BuildContext context,
    Usina usina,
    MetricasGerais metricas,
    NumberFormat moeda,
    NumberFormat numero,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color.fromARGB(78, 56, 161, 247)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        surfaceTintColor: Colors.transparent, // <-- Adicione esta linha
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          hoverColor: Colors.blueGrey.shade50,
          onTap: () => onTapUsina(usina), // CHAMA A LÓGICA DE NAVEGAÇÃO WEB
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: usina.isGeradora
                        ? Colors.orange.withValues(alpha: 0.1)
                        : Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    usina.isGeradora ? Icons.wb_sunny : Icons.home_work,
                    color: usina.isGeradora ? Colors.orange : Colors.blue,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        usina.nome,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        usina.isGeradora
                            ? 'Gerou: ${numero.format(metricas.totalGeradoKwh)} kWh'
                            : 'Recebeu: ${numero.format(metricas.totalInjetadoKwh)} kWh',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Economia Total',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      moeda.format(metricas.valorTotalEconomizadoR),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
