import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/brand.dart';
import 'core/session.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/outbox.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final session = Session();
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: session),
      ChangeNotifierProvider.value(value: Outbox.instance),
    ],
    child: const SiteApp(),
  ));
  await session.load();
}

class SiteApp extends StatelessWidget {
  const SiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Brand.purple, brightness: b),
          cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6)),
          inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        );
    return MaterialApp(
      title: Brand.appName,
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: Consumer<Session>(
        builder: (_, s, __) {
          if (!s.ready) return const _Splash();
          return s.isLoggedIn ? const HomeShell() : const LoginScreen();
        },
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Image(image: AssetImage(Brand.logo), width: 120, height: 120),
          SizedBox(height: 16),
          Text(Brand.appName, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          SizedBox(height: 24),
          CircularProgressIndicator(),
        ])),
      );
}
