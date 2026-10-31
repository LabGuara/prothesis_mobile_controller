import 'package:flutter/material.dart';
import 'config/mqtt_config.dart';
import 'l10n/app_localizations.dart';
import 'screens/main_navigation.dart';
import 'services/collect_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MqttConfig.load();
  final collectStore = await CollectStore.load();
  runApp(MyApp(collectStore: collectStore));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.collectStore});

  final CollectStore collectStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Prosthesis Mobile Controller',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        useMaterial3: true,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MainNavigation(collectStore: collectStore),
    );
  }
}
