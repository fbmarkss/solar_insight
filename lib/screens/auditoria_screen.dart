// Caminho: lib/screens/auditoria_screen.dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../models/usina.dart';
import '../models/lancamento.dart';
import '../utils/calculadora_energetica.dart';
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
          // LAYOUT WEB: BENTO GRID DE CARDS
          // ===============================================================
          return GridView.builder(
            padding: const EdgeInsets.all(32),
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
          );
        } else {
          // ===============================================================
          // LAYOUT MOBILE: MANTIDO EXATAMENTE COMO O ORIGINAL
          // ===============================================================
          return ListView.builder(
            padding: const EdgeInsets.all(16),
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
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
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
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
                  onTap: () =>
                      onTapUsina(usina), // CHAMA A LÓGICA DE NAVEGAÇÃO EXTERNA
                ),
              );
            },
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
        border: Border.all(color: Colors.grey.shade200),
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
