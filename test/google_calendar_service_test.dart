import 'package:flutter_test/flutter_test.dart';
import 'package:taskdam/models/task.dart';
import 'package:taskdam/services/google_calendar_service.dart';

void main() {
  test('Calendar starts disconnected and Firebase sign-out clears its session',
      () {
    final service = GoogleCalendarService();

    expect(service.isConnected, isFalse);
    expect(service.connectedEmail, isNull);

    service.pauseForFirebaseSignOut();

    expect(service.isConnected, isFalse);
    expect(service.connectedEmail, isNull);
  });

  test('disconnect is safe when Calendar is not connected', () async {
    final service = GoogleCalendarService();

    await service.disconnect();

    expect(service.isConnected, isFalse);
    expect(service.connectedEmail, isNull);
  });

  test('sync requires a Calendar session', () {
    final service = GoogleCalendarService();
    final task = TaskItem(
      id: 'task-1',
      day: 'Lunes',
      subject: 'Matemáticas',
      message: 'Repasar',
      color: '#2787A0',
      weekStart: DateTime(2026, 10, 5),
      isExam: false,
      completed: false,
    );

    expect(
      service.syncTask(task, update: false),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Conecta Google Calendar primero.',
        ),
      ),
    );
  });
}
