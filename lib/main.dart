// Caminho: lib/main.dart
// Descrição: Inicialização Híbrida (Web + Mobile + Windows) com Firebase, Hive e Providers.
// CORREÇÕES DESTA VERSÃO:
//   1. Persistência de login robusta (initialData no StreamBuilder) — corrige deslogamento no Android.
//   2. setPersistence apenas na Web (Android/iOS/Windows já persistem automaticamente).
//   3. Lifecycle observer para disparar sync best-effort quando o app vai para background.
//   4. main() e SolarInsightApp entregues juntos, num único bloco íntegro.

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // kIsWeb, AppLifecycleState
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart'; // Importante para Mobile/Desktop
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // Variáveis de ambiente

// Arquivo gerado pelo comando 'flutterfire configure'
import 'firebase_options.dart';

import 'models/usina.dart';
import 'models/lancamento.dart';
import 'services/dashboard_provider.dart';
import 'services/subscription_provider.dart';
import 'services/sincronizacao_service.dart'; // ✅ NOVO: para o ciclo de vida
import 'screens/auth/login_screen.dart';
import 'screens/main_navigation_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Carrega as variáveis de ambiente (Chave do Gemini) ANTES de rodar o app
  await dotenv.load(fileName: "assets/geminiapp/gemini.txt");

  // 2. Inicializa Firebase com Opções (CRUCIAL PARA WEB)
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // --- FORÇA PERSISTÊNCIA DO LOGIN NA WEB ---
  // ⚠️ setPersistence SÓ existe/funciona na Web.
  // No Android/iOS/Windows o Firebase Auth persiste automaticamente
  // via SharedPreferences/Keychain/arquivo local.
  if (kIsWeb) {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  }

  // 3. Inicializa Hive (Lógica Híbrida Web/Mobile/Desktop)
  if (kIsWeb) {
    await Hive.initFlutter();
  } else {
    final appDocumentDir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter(appDocumentDir.path);
  }

  // Registra Adaptadores
  Hive.registerAdapter(UsinaAdapter());
  Hive.registerAdapter(LancamentoMensalAdapter());
  Hive.registerAdapter(InversorItemAdapter());
  Hive.registerAdapter(PainelItemAdapter());
  Hive.registerAdapter(InvestimentoItemAdapter());
  Hive.registerAdapter(BeneficiariaItemAdapter());

  // 4. Abre as Boxes
  await Hive.openBox<Usina>('usinas');
  await Hive.openBox<LancamentoMensal>('lancamentos');
  await Hive.openBox('sync_queue'); // Fila de sincronização
  await Hive.openBox('sync_metadata'); // Controle de datas da última sync

  // 5. Configuração de Localização Brasileira
  await initializeDateFormatting('pt_BR', null);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
      ],
      child: const SolarInsightApp(),
    ),
  );
}

// =============================================================================
// APLICAÇÃO PRINCIPAL
// =============================================================================
class SolarInsightApp extends StatefulWidget {
  const SolarInsightApp({super.key});

  @override
  State<SolarInsightApp> createState() => _SolarInsightAppState();
}

class _SolarInsightAppState extends State<SolarInsightApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // Registra o observer de ciclo de vida (background / fechamento)
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // =========================================================================
  // CAMADA 2: Sync best-effort quando o app vai para background/fechar
  // -------------------------------------------------------------------------
  // Web: chamado ao trocar de aba (não garante fechamento de aba)
  // Mobile/Windows: chamado ao minimizar/fechar
  // O sync é fire-and-forget: NÃO bloqueia, pois o SO pode matar o processo.
  // A garantia total vem do botão "Sair" (SessionManager.logout).
  // =========================================================================
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      SincronizacaoService.dispararSyncEmergencial();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SolarInsight',
      debugShowCheckedModeBanner: false,
      locale: const Locale('pt', 'BR'),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        datePickerTheme: const DatePickerThemeData(
          headerBackgroundColor: Colors.deepOrange,
          headerForegroundColor: Colors.white,
        ),
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('pt', 'BR')],

      // --- LÓGICA DE PERSISTÊNCIA DE LOGIN ---
      // ✅ initialData: restaura imediatamente o usuário do cache local do Firebase Auth,
      //    evitando "flash" de tela de login no cold start do Android.
      // ✅ ConnectionState.waiting só bloqueia a UI se ainda não temos usuário em cache.
      // ✅ Única fonte de verdade: LoginScreen NÃO redireciona manualmente.
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        initialData: FirebaseAuth.instance.currentUser,
        builder: (context, snapshot) {
          // Só mostra o loading se realmente não sabemos ainda o estado do usuário.
          if (snapshot.connectionState == ConnectionState.waiting &&
              snapshot.data == null) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: Colors.deepOrange),
              ),
            );
          }

          if (snapshot.hasData && snapshot.data != null) {
            return const MainNavigationScreen();
          }

          return const LoginScreen();
        },
      ),
    );
  }
}
