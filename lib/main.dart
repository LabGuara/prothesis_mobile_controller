import 'package:flutter/material.dart';
import 'config/mqtt_config.dart';
import 'l10n/app_localizations.dart';
import 'screens/main_navigation.dart';
import 'services/collection_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MqttConfig.load();
  final collectionStore = await CollectionStore.load();
  runApp(MyApp(collectionStore: collectionStore));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.collectionStore});

  final CollectionStore collectionStore;

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
      home: MainNavigation(collectionStore: collectionStore),
    );
  }
}
