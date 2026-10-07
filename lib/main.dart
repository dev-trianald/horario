import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

import 'firebase_options.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var firebaseConfigured = false;
  String? configurationError;

  try {
    final options = DefaultFirebaseOptions.currentPlatform;
    firebaseConfigured = options.apiKey.isNotEmpty &&
        options.appId.isNotEmpty &&
        options.messagingSenderId.isNotEmpty &&
        options.projectId.isNotEmpty;
    if (firebaseConfigured) {
      await initializeFirebase();
    } else {
      configurationError =
          'Faltan las opciones de Firebase de esta plataforma.';
    }
  } catch (error) {
    configurationError = error.toString();
  }

  runApp(TaskDamApp(
    firebaseConfigured: firebaseConfigured,
    configurationError: configurationError,
  ));
}

class TaskDamApp extends StatelessWidget {
  const TaskDamApp({
    super.key,
    required this.firebaseConfigured,
    this.configurationError,
  });

  final bool firebaseConfigured;
  final String? configurationError;

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
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: Color(0xFF46565A)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: Color(0xFF46565A)),
          ),
        ),
      ),
      home: firebaseConfigured
          ? HomeScreen(
              auth: FirebaseAuth.instance,
              firestore: FirebaseFirestore.instance,
            )
          : ConfigurationPage(error: configurationError),
    );
  }
}

class ConfigurationPage extends StatelessWidget {
  const ConfigurationPage({super.key, this.error});

  final String? error;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.calendar_month,
                      size: 42, color: Color(0xFF46C4B2)),
                  const SizedBox(height: 20),
                  Text('TaskDAM',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 12),
                  if (defaultTargetPlatform == TargetPlatform.linux) ...[
                    const Text(
                      'La versión de escritorio para Linux no puede conectarse a Firebase: Firebase Authentication y Cloud Firestore no tienen soporte nativo para Linux en esta app. No se soluciona ejecutando flutterfire configure.',
                    ),
                    const SizedBox(height: 12),
                    const Text('Mientras tanto, puedes usar la versión web:'),
                    const SelectableText('https://horario-eba89.web.app/'),
                  ] else ...[
                    const Text(
                      'Configura Firebase ejecutando flutterfire configure desde la raíz del proyecto. El asistente generará las opciones necesarias para web, Android e iOS.',
                    ),
                  ],
                  if (error != null &&
                      defaultTargetPlatform != TargetPlatform.linux) ...[
                    const SizedBox(height: 12),
                    Text(error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
}
