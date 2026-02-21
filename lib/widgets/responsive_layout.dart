// Caminho: lib/widgets/responsive_layout.dart
// Descrição: Layout com Sidebar fixo em 1200px para Web, integrado ao Firestore para dados de utilizador reais.

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ResponsiveLayout extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTabTapped;
  final List<Widget> pages;
  final List<String> titulos;
  final List<IconData> icones;

  // Parâmetros Mobile
  final PreferredSizeWidget? mobileAppBar;
  final Widget? mobileDrawer;
  final Widget? mobileFab;

  // Callbacks Web
  final VoidCallback? onSyncTap;
  final Function(int)? onAdminItemTap;

  const ResponsiveLayout({
    super.key,
    required this.currentIndex,
    required this.onTabTapped,
    required this.pages,
    required this.titulos,
    required this.icones,
    this.mobileAppBar,
    this.mobileDrawer,
    this.mobileFab,
    this.onSyncTap,
    this.onAdminItemTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Breakpoint para Sidebar
        bool isDesktop = constraints.maxWidth >= 900;

        if (!isDesktop) {
          // --- MOBILE (Layout de Lista Original) ---
          int mobileIndex = currentIndex > 2 ? 0 : currentIndex;

          return Scaffold(
            appBar: mobileAppBar,
            endDrawer: mobileDrawer,
            body: pages[currentIndex],
            floatingActionButton: mobileFab,
            bottomNavigationBar: NavigationBar(
              backgroundColor: Colors.white,
              elevation: 4,
              selectedIndex: mobileIndex,
              onDestinationSelected: onTabTapped,
              indicatorColor: Colors.deepOrange.withValues(alpha: 0.2),
              destinations: List.generate(titulos.length, (index) {
                return NavigationDestination(
                  icon: Icon(icones[index]),
                  label: titulos[index],
                  selectedIcon: Icon(icones[index], color: Colors.deepOrange),
                );
              }),
            ),
          );
        } else {
          // --- WEB DESKTOP (Fixado em 1200px) ---
          return Scaffold(
            backgroundColor: const Color(0xFFF0F2F5),
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWebSidebar(context),
                Expanded(
                  child: Container(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      // AJUSTE SOLICITADO: Trava o tamanho máximo em 1200
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: pages[currentIndex],
                    ),
                  ),
                ),
              ],
            ),
            floatingActionButton: mobileFab,
          );
        }
      },
    );
  }

  // --- COMPONENTES DA SIDEBAR (MANTIDOS E ATUALIZADOS) ---

  Widget _buildWebSidebar(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final bool isLogado = user != null;

    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          // =========================================================
          // LOGO E TÍTULO (Com Degradê Azul)
          // =========================================================
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 32),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color.fromARGB(255, 6, 153, 252),
                  const Color.fromARGB(255, 162, 213, 243),
                ], // Degradê Azul
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 120,
                  width: 120,
                  // O ClipRRect vai "barbear" a borda serrilhada/laranja externa
                  child: ClipRRect(
                    // Se o seu arredondamento original for maior, pode aumentar este valor
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/logoweb.png',
                      fit: BoxFit
                          .cover, // Preenche o espaço cortando a aresta defeituosa
                      filterQuality: FilterQuality
                          .high, // Força a melhor qualidade de redução
                      isAntiAlias: true, // Suaviza as bordas na Web
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'SolarInsight',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors
                        .white, // Fonte branca para destacar no fundo azul
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          // =========================================================
          // =========================================================

          // --- AREA PROTEGIDA POR PERFIL (CABEÇALHO + MENUS) ---
          Expanded(
            child: FutureBuilder<DocumentSnapshot>(
              future: isLogado
                  ? FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .get()
                  : null,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.deepOrange),
                  );
                }

                final userData = snapshot.data?.data() as Map<String, dynamic>?;

                // A CHAVE DO CADEADO PARA OS MENUS:
                final bool isAdmin = userData?['role'] == 'admin';

                final String nomeEmpresa = userData?['nomeEmpresa'] ?? "";
                final String nomeUsuarioFirestore =
                    userData?['nome'] ?? "Carregando...";

                final String cargo = isAdmin ? "Administrador" : "Usuário";

                final letraInicial =
                    nomeUsuarioFirestore.isNotEmpty &&
                        nomeUsuarioFirestore != "Carregando..."
                    ? nomeUsuarioFirestore[0].toUpperCase()
                    : "U";

                return Column(
                  children: [
                    // --- 1. CABEÇALHO DO UTILIZADOR ---
                    Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F7FA),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.white,
                            radius: 16,
                            child: Text(
                              letraInicial,
                              style: const TextStyle(
                                color: Colors.deepOrange,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nomeEmpresa.isNotEmpty
                                      ? "$nomeUsuarioFirestore | $nomeEmpresa"
                                      : nomeUsuarioFirestore,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Colors.black87,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                Text(
                                  cargo,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // --- 2. MENUS DE NAVEGAÇÃO ---
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          _buildSectionHeader('PRINCIPAL'),
                          ...List.generate(titulos.length, (index) {
                            return _buildMenuItem(
                              icon: icones[index],
                              label: titulos[index],
                              isSelected: currentIndex == index,
                              onTap: () => onTabTapped(index),
                            );
                          }),

                          // ==========================================================
                          // CADEADO: Só renderiza se for Administrador!
                          // ==========================================================
                          if (isAdmin) ...[
                            const SizedBox(height: 24),
                            _buildSectionHeader('ADMINISTRAÇÃO'),
                            _buildMenuItem(
                              icon: Icons.business,
                              label: 'Plano e Empresa',
                              isSelected: currentIndex == 3,
                              onTap: () => onAdminItemTap?.call(3),
                            ),
                            _buildMenuItem(
                              icon: Icons.group_outlined,
                              label: 'Equipe',
                              isSelected: currentIndex == 4,
                              onTap: () => onAdminItemTap?.call(4),
                            ),
                            _buildMenuItem(
                              icon: Icons.history_edu,
                              label: 'Logs do Sistema',
                              isSelected: currentIndex == 5,
                              onTap: () => onAdminItemTap?.call(5),
                            ),
                            _buildMenuItem(
                              icon: Icons.cloud_download_outlined,
                              label: 'Backup & Dados',
                              isSelected: currentIndex == 6,
                              onTap: () => onAdminItemTap?.call(6),
                            ),
                            _buildMenuItem(
                              icon: Icons.settings_outlined,
                              label: 'Configurações',
                              isSelected: currentIndex == 7,
                              onTap: () => onAdminItemTap?.call(7),
                            ),
                          ],
                          // ==========================================================
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          const Divider(height: 1),

          // --- Rodapé (Sincronizar e Sair) SEMPRE VISÍVEL ---
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _buildMenuItem(
                  icon: Icons.sync,
                  label: 'Sincronizar',
                  iconColor: Colors.blue,
                  onTap: () => onSyncTap?.call(),
                ),
                _buildMenuItem(
                  icon: Icons.logout_rounded,
                  label: 'Sair',
                  iconColor: Colors.red,
                  onTap: () async => await FirebaseAuth.instance.signOut(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 8, top: 8),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.grey.shade500,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    bool isSelected = false,
    Color? iconColor,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: Colors.grey.shade100,
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.deepOrange.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected
                      ? Colors.deepOrange
                      : (iconColor ?? Colors.grey.shade600),
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? Colors.deepOrange
                        : (iconColor ?? Colors.grey.shade800),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
