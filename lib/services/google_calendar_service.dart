import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../models/task.dart';

class GoogleCalendarService {
  GoogleCalendarService({http.Client? client}) : _client = client ?? http.Client();

  static const _calendarScope =
      'https://www.googleapis.com/auth/calendar.events';

  final http.Client _client;
  GoogleSignIn? _googleSignIn;
  GoogleSignInAccount? _account;
  String? _accessToken;
  String? _email;

  bool get isConnected => _accessToken != null;
  String? get connectedEmail => _email;

  GoogleSignIn get _signIn => _googleSignIn ??= GoogleSignIn(
      scopes: ['email', _calendarScope],
      );

  Future<String?> connect(String firebaseEmail) async {
    final account = await _signIn.signIn();
    if (account == null) return null;

    final connectedEmail = await _activateAccount(account, firebaseEmail);
    if (connectedEmail == null) return null;

    return connectedEmail;
  }

  Future<String?> _activateAccount(
      GoogleSignInAccount account, String firebaseEmail) async {
    final authentication = await account.authentication;
    final accessToken = authentication.accessToken;
    if (accessToken == null) {
      throw StateError('Google no devolvió permiso para acceder al calendario.');
    }

    final email = account.email.trim();
    if (email.toLowerCase() != firebaseEmail.trim().toLowerCase()) {
      _clearSession();
      throw StateError(
          'Conecta Google Calendar con la misma cuenta usada para iniciar sesión: $firebaseEmail.');
    }

    _account = account;
    _accessToken = accessToken;
    _email = email;
    return email;
  }

  Future<void> disconnect() async {
    if (_account != null) await _signIn.disconnect();
    _clearSession();
  }

  void pauseForFirebaseSignOut() {
    _clearSession();
  }

  void _clearSession() {
    _account = null;
    _accessToken = null;
    _email = null;
  }

  Future<void> syncTask(TaskItem task, {required bool update}) async {
    final token = _requireToken();
    final eventId = _eventId(task.id);
    final endpoint = Uri.https(
      'www.googleapis.com',
      '/calendar/v3/calendars/primary/events/$eventId',
    );
    final collection = Uri.https(
      'www.googleapis.com',
      '/calendar/v3/calendars/primary/events',
    );
    final event = _eventData(task);
    final response = update
        ? await _client.patch(
            endpoint,
            headers: _headers(token),
            body: jsonEncode(event),
          )
        : await _client.post(
            collection,
            headers: _headers(token),
            body: jsonEncode({'id': eventId, ...event}),
          );

    if (update && response.statusCode == 404) {
      await syncTask(task, update: false);
      return;
    }
    if (!update && response.statusCode == 409) {
      final existing = await _client.get(endpoint, headers: _headers(token));
      if (existing.statusCode == 200) {
        final existingEvent = jsonDecode(existing.body) as Map<String, dynamic>;
        final privateProperties =
            existingEvent['extendedProperties']?['private'];
        if (privateProperties is Map<String, dynamic> &&
            privateProperties['taskdamTaskId'] == task.id) {
          await _client.patch(
            endpoint,
            headers: _headers(token),
            body: jsonEncode(event),
          );
          return;
        }
      }
    } else if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw StateError(_apiError(response, 'No se pudo sincronizar con Google Calendar.'));
  }

  Future<void> deleteTask(String taskId) async {
    final response = await _client.delete(
      Uri.https(
        'www.googleapis.com',
        '/calendar/v3/calendars/primary/events/${_eventId(taskId)}',
      ),
      headers: _headers(_requireToken()),
    );
    if (response.statusCode == 404 ||
        response.statusCode == 410 ||
        (response.statusCode >= 200 && response.statusCode < 300)) {
      return;
    }
    throw StateError(_apiError(response, 'No se pudo borrar el evento de Google Calendar.'));
  }

  String _requireToken() {
    final token = _accessToken;
    if (token == null) throw StateError('Conecta Google Calendar primero.');
    return token;
  }

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  Map<String, dynamic> _eventData(TaskItem task) {
    const dayOffsets = {
      'Lunes': 0,
      'Martes': 1,
      'Miércoles': 2,
      'Jueves': 3,
      'Viernes': 4,
    };
    final offset = dayOffsets[task.day];
    if (offset == null) throw StateError('No se reconoce el día de la tarea.');

    final start = DateTime.utc(
      task.weekStart.year,
      task.weekStart.month,
      task.weekStart.day + offset,
    );
    final end = start.add(const Duration(days: 1));
    final startDate = _dateString(start);
    final endDate = _dateString(end);
    return {
      'summary':
          '${task.isExam ? 'Examen' : 'Tarea'} · ${task.subject}: ${task.message}',
      'description':
          'Apunte de TaskDAM\nAsignatura: ${task.subject}\nDía: ${task.day}',
      'start': {'date': startDate},
      'end': {'date': endDate},
      'extendedProperties': {
        'private': {'taskdamTaskId': task.id},
      },
    };
  }

  String _dateString(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String _eventId(String taskId) => utf8
      .encode(taskId)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  String _apiError(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final error = body['error'];
      if (error is Map<String, dynamic> && error['message'] is String) {
        return error['message'] as String;
      }
    } catch (_) {}
    return fallback;
  }
}