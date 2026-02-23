// Caminho: lib/screens/usinas_list_screen.dart
// Descrição: Lista de Usinas com Navegador Aninhado, Pull-to-Refresh e Limites do Plano Freemium com bloqueio para Funcionários.

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import '../models/usina.dart';
import 'cadastro_usina_screen.dart';
import 'usina_detalhes_screen.dart';
import 'paywall_screen.dart';
import '../services/sincronizacao_service.dart';
import '../services/subscription_provider.dart';
import '../utils/app_feedback.dart';

class UsinasListScreen extends StatefulWidget {
  const UsinasListScreen({super.key});

  @override
  State<UsinasListScreen> createState() => _UsinasListScreenState();
}

class _UsinasListScreenState extends State<UsinasListScreen> {
  // A "mágica" para a Web: Um navegador independente que não esconde o Menu Lateral
  final GlobalKey<NavigatorState> _nestedNavKey = GlobalKey<NavigatorState>();

  // --- NOVA LÓGICA DE PULL-TO-REFRESH COM FEEDBACK PADRONIZADO ---
  Future<void> _handleRefresh(BuildContext context) async {
    try {
      final resultado = await SincronizacaoService().sincronizarTudo();

      // Força o guardião a verificar se o plano mudou no servidor
      if (context.mounted) {
        Provider.of<SubscriptionProvider>(
          context,
          listen: false,
        ).carregarPlanoDoServidor();
      }

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

  // --- LÓGICA DE NAVEGAÇÃO E VERIFICAÇÃO DE LIMITE (COM REGRA DE CARGO) ---
  void _tentarCriarNovaUsina(bool isWeb, BuildContext localContext) {
    // 1. Instancia o Guardião e o Banco de Usinas
    final subProvider = Provider.of<SubscriptionProvider>(
      localContext,
      listen: false,
    );
    final box = Hive.box<Usina>('usinas');

    // 2. Conta quantas Geradoras e Beneficiárias o usuário já possui
    final totalGeradorasAtuais = box.values
        .where((u) => u.isGeradora && !u.isDeletado)
        .length;
    final totalBeneficiariasAtuais = box.values
        .where((u) => !u.isGeradora && !u.isDeletado)
        .length;

    // 3. Verifica se ele está BLOQUEADO TOTALMENTE (Não pode geradora NEM beneficiária)
    if (!subProvider.podeAdicionarUsinaGeradora(totalGeradorasAtuais) &&
        !subProvider.podeAdicionarUsinaFilha(totalBeneficiariasAtuais)) {
      // 4. VERIFICA SE É ADMIN OU FUNCIONÁRIO
      if (subProvider.isAdmin) {
        // ABRE A VITRINE DE VENDAS SE FOR ADMIN
        _abrirTela(
          const PaywallScreen(
            mensagemMotivo:
                "Limite total de unidades atingido no Plano Grátis.",
          ),
          isWeb,
          localContext,
        );
      } else {
        // MOSTRA AVISO SE FOR FUNCIONÁRIO
        AppFeedback.show(
          localContext,
          "🔒 Limite atingido. Solicite ao administrador da equipe que faça o upgrade para o plano PRO.",
          isError: true,
        );
      }
      return;
    }

    // Se ele ainda puder adicionar algo, abre a tela de cadastro normal.
    _abrirTela(const CadastroUsinaScreen(), isWeb, localContext);
  }

  void _abrirTela(Widget tela, bool isWeb, BuildContext localContext) {
    if (isWeb) {
      // Na Web: Abre a tela DENTRO da "gaiola" direita
      _nestedNavKey.currentState!.push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => tela,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } else {
      // No Telemóvel: Comportamento normal
      Navigator.push(localContext, MaterialPageRoute(builder: (_) => tela));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Usa a largura total do navegador para saber se é Web ou Mobile
    bool isWeb = MediaQuery.of(context).size.width >= 900;

    if (isWeb) {
      // LAYOUT WEB: NAVEGADOR ANINHADO
      return Navigator(
        key: _nestedNavKey,
        onGenerateRoute: (settings) {
          return MaterialPageRoute(
            builder: (context) => _buildListaConteudo(isWeb),
          );
        },
      );
    } else {
      // LAYOUT MOBILE
      return _buildListaConteudo(isWeb);
    }
  }

  // O Conteúdo principal que observa as mudanças no Banco de Dados
  Widget _buildListaConteudo(bool isWeb) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: ValueListenableBuilder(
        valueListenable: Hive.box<Usina>('usinas').listenable(),
        builder: (context, Box<Usina> box, _) {
          final usinas = box.values.where((u) => !u.isDeletado).toList();

          if (isWeb) {
            return _buildWebLayout(usinas, isWeb, context);
          } else {
            return _buildMobileLayout(usinas, isWeb, context);
          }
        },
      ),
      // MÁGICA AQUI: Se for Web, o botão flutuante é "null" (desaparece). Se for mobile, ele aparece.
      floatingActionButton: isWeb
          ? null
          : FloatingActionButton.extended(
              backgroundColor: Colors.deepOrange,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Nova Unidade',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: () => _tentarCriarNovaUsina(
                isWeb,
                context,
              ), // <-- CHAMA A VALIDAÇÃO
            ),
    );
  }

  // ===========================================================================
  // LAYOUTS ESPECÍFICOS (WEB E MOBILE)
  // ===========================================================================

  Widget _buildWebLayout(List<Usina> usinas, bool isWeb, BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => _handleRefresh(context),
      color: Colors.deepOrange,
      backgroundColor: Colors.white,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Meus Ativos',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey[900],
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        'Gerencie suas unidades geradoras e beneficiárias',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.blueGrey[400],
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _tentarCriarNovaUsina(
                    isWeb,
                    context,
                  ), // <-- CHAMA A VALIDAÇÃO
                  icon: const Icon(Icons.add),
                  label: const Text('Nova Unidade'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            _buildWebSummaryRow(usinas),
            const SizedBox(height: 32),
            if (usinas.isEmpty)
              _buildEmptyState(isWeb, context)
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 450,
                  childAspectRatio: 2.2,
                  crossAxisSpacing: 24,
                  mainAxisSpacing: 24,
                ),
                itemCount: usinas.length,
                itemBuilder: (context, index) {
                  return _buildUsinaCardWeb(context, usinas[index], isWeb);
                },
              ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout(
    List<Usina> usinas,
    bool isWeb,
    BuildContext context,
  ) {
    return RefreshIndicator(
      color: Colors.deepOrange,
      backgroundColor: Colors.white,
      onRefresh: () => _handleRefresh(context),
      child: ListView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Meus Ativos',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  color: Colors.black87,
                ),
              ),
              Text(
                'Gerencie suas unidades',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (usinas.isEmpty)
            _buildEmptyState(isWeb, context)
          else
            ...usinas.map((usina) => _buildUsinaCard(context, usina, isWeb)),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ===========================================================================
  // WIDGETS EXCLUSIVOS WEB E MOBILE
  // ===========================================================================

  Widget _buildWebSummaryRow(List<Usina> usinas) {
    int total = usinas.length;
    int geradoras = usinas.where((u) => u.isGeradora).length;
    int beneficiarias = total - geradoras;
    int inativas = usinas.where((u) => !u.ativa).length;

    return Row(
      children: [
        Expanded(
          child: _buildSummaryPill(
            'Total Unidades',
            '$total',
            Icons.business,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildSummaryPill(
            'Geradoras',
            '$geradoras',
            Icons.wb_sunny_outlined,
            Colors.orange,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildSummaryPill(
            'Beneficiárias',
            '$beneficiarias',
            Icons.home_work_outlined,
            Colors.teal,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildSummaryPill(
            'Inativas',
            '$inativas',
            Icons.warning_amber_rounded,
            Colors.red,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryPill(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsinaCardWeb(BuildContext context, Usina usina, bool isWeb) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          hoverColor: Colors.blueGrey.shade50,
          onTap: () =>
              _abrirTela(UsinaDetalhesScreen(usina: usina), isWeb, context),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: usina.isGeradora
                            ? Colors.orange.withValues(alpha: 0.1)
                            : Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        usina.isGeradora ? Icons.wb_sunny : Icons.home_work,
                        color: usina.isGeradora ? Colors.orange : Colors.blue,
                        size: 24,
                      ),
                    ),
                    if (!usina.ativa)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Arquivada',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      usina.nome,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.blueGrey.shade900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          'UC: ${usina.id}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blueGrey.shade400,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            usina.isGeradora ? 'Geradora' : 'Beneficiária',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildUsinaCard(BuildContext context, Usina usina, bool isWeb) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () =>
            _abrirTela(UsinaDetalhesScreen(usina: usina), isWeb, context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: usina.isGeradora
                      ? Colors.orange.withValues(alpha: 0.1)
                      : Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
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
                  children: [
                    Text(
                      usina.nome,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'UC: ${usina.id}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            usina.isGeradora ? 'Geradora' : 'Beneficiária',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (!usina.ativa) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Arquivada',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isWeb, BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.solar_power_outlined,
              size: 80,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhuma usina cadastrada',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 8),
            if (!isWeb)
              ElevatedButton.icon(
                onPressed: () => _tentarCriarNovaUsina(
                  isWeb,
                  context,
                ), // <-- CHAMA A VALIDAÇÃO AQUI TAMBÉM
                icon: const Icon(Icons.add),
                label: const Text('Nova Unidade'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              )
            else
              const Text(
                'Clique em "Nova Unidade" lá no topo para começar.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }
}
