// Caminho: lib/widgets/responsive_layout.dart
// Descrição: Layout com Sidebar fixo em 1200px para Web, integrado ao Firestore para dados de utilizador reais.
// ALTERAÇÃO DESTA VERSÃO:
//   - Botão "Sair" da sidebar Web agora usa SessionManager.logout(context)
//     em vez de FirebaseAuth.instance.signOut() direto.
//   - Isso garante: sync best-effort → limpeza de Hive → reset de Providers
//     → reset do motor reativo → signOut. Elimina contaminação entre usuários.
//   - Todo o resto permanece intacto.

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/session_manager.dart'; // <-- NOVO IMPORT

class ResponsiveLayout extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTabTapped;
  final List<Widget> pages;
  final List<String> titulos;
  final List<IconData> icones;

  final PreferredSizeWidget? mobileAppBar;
  final Widget? mobileDrawer;
  final Widget? mobileFab;

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
        bool isDesktop = constraints.maxWidth >= 800;

        if (!isDesktop) {
          int mobileIndex = currentIndex > 2 ? 0 : currentIndex;

          return Scaffold(
            appBar: mobileAppBar,
            endDrawer: mobileDrawer,
            // 1. MÁGICA PARA O MOBILE/TABLET EM PÉ: Protege o conteúdo central
            body: SafeArea(child: pages[currentIndex]),
            floatingActionButton: mobileFab,
            // 2. MÁGICA PARA O MOBILE/TABLET EM PÉ: Protege o menu inferior
            bottomNavigationBar: SafeArea(
              child: NavigationBar(
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
            ),
          );
        } else {
          return Scaffold(
            backgroundColor: const Color(0xFFF0F2F5),
            // 3. MÁGICA PARA O TABLET DEITADO / DESKTOP: Protege o Menu e o Conteúdo
            body: SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildWebSidebar(context),
                  Expanded(
                    child: Container(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
                        child: pages[currentIndex],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            floatingActionButton: mobileFab,
          );
        }
      },
    );
  }

  Widget _buildWebSidebar(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final bool isLogado = user != null;

    // --- ESTADO INICIAL (Imediato da Sessão) ---
    final String emailSessao = user?.email ?? "Usuário";
    final String letraBase = emailSessao.isNotEmpty
        ? emailSessao[0].toUpperCase()
        : "U";

    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 32),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color.fromARGB(255, 6, 153, 252),
                  Color.fromARGB(255, 162, 213, 243),
                ],
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
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/logoweb.png',
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      isAntiAlias: true,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'SolarInsight',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: FutureBuilder<DocumentSnapshot>(
              future: isLogado
                  ? FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .get()
                  : null,
              builder: (context, snapshot) {
                // --- FALLBACK IMEDIATO ENQUANTO CARREGA ---
                bool isAdmin = false;
                String nomeExibido = emailSessao.split('@').first;
                String cargoExibido = "Sincronizando...";

                if (snapshot.hasData && snapshot.data!.exists) {
                  final userData =
                      snapshot.data!.data() as Map<String, dynamic>?;
                  isAdmin = userData?['role'] == 'admin';

                  final String nomeEmpresa = userData?['nomeEmpresa'] ?? "";
                  final String nomeFirestore = userData?['nome'] ?? nomeExibido;

                  nomeExibido = nomeEmpresa.isNotEmpty
                      ? "$nomeFirestore | $nomeEmpresa"
                      : nomeFirestore;

                  cargoExibido = isAdmin ? "Administrador" : "Usuário";
                }

                return Column(
                  children: [
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
                              letraBase,
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
                                  nomeExibido,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Colors.black87,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                Text(
                                  cargoExibido,
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

                          const SizedBox(height: 24),
                          _buildSectionHeader('ADMINISTRAÇÃO'),

                          // --- APENAS ADMIN ---
                          if (isAdmin)
                            _buildMenuItem(
                              icon: Icons.business,
                              label: 'Plano e Empresa',
                              isSelected: currentIndex == 3,
                              onTap: () => onAdminItemTap?.call(3),
                            ),

                          // --- TODOS VEEM (Equipe) ---
                          _buildMenuItem(
                            icon: Icons.group_outlined,
                            label: 'Equipe',
                            isSelected: currentIndex == 4,
                            onTap: () => onAdminItemTap?.call(4),
                          ),

                          // --- APENAS ADMIN ---
                          if (isAdmin) ...[
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
                          ],

                          // --- TODOS VEEM (Configurações) ---
                          _buildMenuItem(
                            icon: Icons.settings_outlined,
                            label: 'Configurações',
                            isSelected: currentIndex == 7,
                            onTap: () => onAdminItemTap?.call(7),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1),
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
                // ============================================================
                // ✅ ALTERAÇÃO: Logout centralizado via SessionManager
                // ------------------------------------------------------------
                // Fluxo completo:
                //   1. Pausa o motor reativo
                //   2. Sync best-effort (timeout 6s)
                //   3. Limpa fila de sync
                //   4. Limpa Hive (usinas, lancamentos, sync_metadata, auth_cache)
                //   5. Reset dos Providers
                //   6. Reset do motor reativo
                //   7. FirebaseAuth.signOut() → StreamBuilder do main troca para Login
                // ============================================================
                _buildMenuItem(
                  icon: Icons.logout_rounded,
                  label: 'Sair',
                  iconColor: Colors.red,
                  onTap: () async {
                    await SessionManager.logout(context);
                  },
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
