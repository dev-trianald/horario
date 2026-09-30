import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/home_screen.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }
  runApp(const TaskDamApp());
}

class TaskDamApp extends StatelessWidget {
  const TaskDamApp({super.key});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF172124);
    const surface = Color(0xFF222E31);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF46C4B2),
      brightness: Brightness.dark,
      surface: surface,
    );

    return MaterialApp(
      title: 'TaskDAM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: ink,
        appBarTheme: const AppBarTheme(
          backgroundColor: ink,
          foregroundColor: Color(0xFFF3F5F3),
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: const CardThemeData(
          color: surface,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: Color(0xFF344246)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF46565A)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF46565A)),
          ),
        ),
      ),
      home: supabaseUrl.isEmpty || supabaseAnonKey.isEmpty
          ? const ConfigurationPage()
          : HomeScreen(client: Supabase.instance.client),
    );
  }
}

class ConfigurationPage extends StatelessWidget {
  const ConfigurationPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.calendar_month, size: 42, color: Color(0xFF46C4B2)),
                  const SizedBox(height: 20),
                  Text('TaskDAM', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 12),
                  const Text(
                    'Falta configurar la conexión con Supabase. Inicia la app pasando SUPABASE_URL y SUPABASE_ANON_KEY como argumentos --dart-define.',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}