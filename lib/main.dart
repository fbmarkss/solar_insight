// Caminho: lib/main.dart
// Descrição: Inicialização Híbrida (Web + Mobile) com Firebase e Hive configurados corretamente.

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // <--- Necessário para verificar se é Web (kIsWeb)
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart'; // Importante para Mobile
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';

// O arquivo abaixo é gerado pelo comando 'flutterfire configure'
import 'firebase_options.dart';

import 'models/usina.dart';
import 'models/lancamento.dart';
import 'services/dashboard_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/main_navigation_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Inicializa Firebase com Opções (CRUCIAL PARA WEB)
  // O DefaultFirebaseOptions detecta se está no Android, iOS ou Web e entrega a chave certa.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 2. Inicializa Hive (Lógica Híbrida Web/Mobile)
  if (kIsWeb) {
    // Na Web, o Hive usa o IndexedDB do navegador automaticamente.
    // Não podemos passar "path" aqui, senão dá erro.
    await Hive.initFlutter();
  } else {
    // No Celular, precisamos definir o diretório de documentos.
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

  // 3. Abre as Boxes
  // Abrimos todas as caixas necessárias para o app não travar tentando acessar uma fechada.
  await Hive.openBox<Usina>('usinas');
  await Hive.openBox<LancamentoMensal>('lancamentos');
  await Hive.openBox('sync_queue'); // Fila de sincronização
  await Hive.openBox('sync_metadata'); // Controle de datas da última sync

  // 4. Configuração de Localização Brasileira
  await initializeDateFormatting('pt_BR', null);

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => DashboardProvider())],
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
      // Força o idioma para PT-BR
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

      // --- LOGICA DE PERSISTÊNCIA DE LOGIN ---
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
