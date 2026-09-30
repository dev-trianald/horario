import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }

    throw UnsupportedError(
      'Esta plataforma aún no está configurada con FlutterFire.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAT-ujXHr4mOCGGY9ZjsOR6-Z1v4UcqfnM',
    appId: '1:470468226376:web:f4769a3e55db273145d77d',
    messagingSenderId: '470468226376',
    projectId: 'horario-eba89',
    authDomain: 'horario-eba89.firebaseapp.com',
  );
}