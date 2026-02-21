// Caminho: lib/main.dart
// Descrição: Inicialização Híbrida (Web + Mobile) com Firebase, Hive e Providers (incluindo Assinatura e Variáveis de Ambiente) configurados.

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // <--- Necessário para verificar se é Web (kIsWeb)
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart'; // Importante para Mobile
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // <--- NOVO IMPORT PARA O .ENV

// O arquivo abaixo é gerado pelo comando 'flutterfire configure'
import 'firebase_options.dart';

import 'models/usina.dart';
import 'models/lancamento.dart';
import 'services/dashboard_provider.dart';
import 'services/subscription_provider.dart'; // <--- IMPORT DO GUARDIÃO
import 'screens/auth/login_screen.dart';
import 'screens/main_navigation_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Carrega as variáveis de ambiente (Chave do Gemini) ANTES de rodar o app
  await dotenv.load(fileName: ".env");

  // 2. Inicializa Firebase com Opções (CRUCIAL PARA WEB)
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // --- FORÇA PERSISTÊNCIA DO LOGIN NA WEB PARA EVITAR O "CARREGANDO" INFINITO ---
  if (kIsWeb) {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  }

  // 3. Inicializa Hive (Lógica Híbrida Web/Mobile)
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

class SolarInsightApp extends StatelessWidget {
  const SolarInsightApp({super.key});

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
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: Colors.deepOrange),
              ),
            );
          }

          if (snapshot.hasData) {
            return const MainNavigationScreen();
          }

          return const LoginScreen();
        },
      ),
    );
  }
}
