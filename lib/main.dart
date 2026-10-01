// Caminho: lib/main.dart
// Descrição: Inicialização Híbrida (Web + Mobile + Windows) com Firebase, Hive e Providers.
//
// CORREÇÃO CRÍTICA DO BUG "F5 PARA ENTRAR":
//   - O StreamBuilder foi MOVIDO PARA FORA do MaterialApp.
//   - Isso força o MaterialApp INTEIRO a ser reconstruído quando o User muda,
//     evitando o cache da rota 'home' que impedia a troca de LoginScreen → MainNavigationScreen.
//   - Mantidas todas as outras correções (initialData, lifecycle observer, setPersistence Web).

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // kIsWeb, AppLifecycleState
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'firebase_options.dart';

import 'models/usina.dart';
import 'models/lancamento.dart';
import 'services/dashboard_provider.dart';
import 'services/subscription_provider.dart';
import 'services/sincronizacao_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/main_navigation_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ CORREÇÃO DE SEGURANÇA:

  await dotenv.load(fileName: "env_config.txt");

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (kIsWeb) {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  }

  if (kIsWeb) {
    await Hive.initFlutter();
  } else {
    final appDocumentDir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter(appDocumentDir.path);
  }

  Hive.registerAdapter(UsinaAdapter());
  Hive.registerAdapter(LancamentoMensalAdapter());
  Hive.registerAdapter(InversorItemAdapter());
  Hive.registerAdapter(PainelItemAdapter());
  Hive.registerAdapter(InvestimentoItemAdapter());
  Hive.registerAdapter(BeneficiariaItemAdapter());

  await Hive.openBox<Usina>('usinas');
  await Hive.openBox<LancamentoMensal>('lancamentos');
  await Hive.openBox('sync_queue');
  await Hive.openBox('sync_metadata');

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
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

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
    // ✅ CORREÇÃO CRÍTICA DO BUG DO F5:
    //
    // O StreamBuilder agora ENVOLVE o MaterialApp (não é mais o 'home').
    // Isso significa que, quando o User muda, o MaterialApp INTEIRO é
    // reconstruído do zero. O Navigator interno perde sua rota 'home'
    // antiga e monta a nova (LoginScreen OU MainNavigationScreen).
    //
    // SEM ISSO: o MaterialApp cacheava a rota 'home' e, mesmo o StreamBuilder
    // recebendo o novo User, o Navigator não trocava a tela — causando o
    // famoso "só entra depois de F5".
    //
    // Removemos o 'initialData' porque, agora que o StreamBuilder está FORA
    // do MaterialApp, ele já resolve o estado inicial sozinho. O 'initialData'
    // era apenas um paliativo para o problema do Android que já foi resolvido
    // por outras vias (setPersistence Web + sessão persistida do Firebase).
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // ─── ESTADO 1: Primeira execução, ainda aguardando o Firebase Auth ───
        // Só mostra loading se REALMENTE não sabemos o estado ainda.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: Colors.deepOrange),
              ),
            ),
          );
        }

        // ─── ESTADO 2: Usuário logado → MainNavigationScreen ───
        if (snapshot.hasData && snapshot.data != null) {
          return _buildMaterialApp(home: const MainNavigationScreen());
        }

        // ─── ESTADO 3: Usuário não logado → LoginScreen ───
        return _buildMaterialApp(home: const LoginScreen());
      },
    );
  }

  /// Constrói o MaterialApp com todo o tema, localização e configurações.
  /// Extraído para método separado para não duplicar código entre os 3 estados.
  Widget _buildMaterialApp({required Widget home}) {
    return MaterialApp(
      // ⚠️ KEY: força o Flutter a tratar cada MaterialApp como uma nova árvore
      // quando o 'home' muda. Isso é o que garante a troca de tela sem F5.
      key: ValueKey(home.runtimeType.toString()),
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
      home: home,
    );
  }
}
