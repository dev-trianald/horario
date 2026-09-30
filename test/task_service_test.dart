import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskdam/services/task_service.dart';

void main() {
  test('stores and loads tasks inside the signed-in user path', () async {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'student-a', email: 'student@example.com'),
    );
    final firestore = FakeFirebaseFirestore();
    final service = TaskService(firestore, auth);

    await service.saveTask(
      day: 'Lunes',
      subject: 'IP2',
      message: 'Preparar la práctica',
      color: '#59666A',
      weekStart: DateTime(2026, 9, 28),
      isExam: false,
    );

    final tasks = await service.loadTasks();
    expect(tasks, hasLength(1));
    expect(tasks.single.subject, 'IP2');
    expect(tasks.single.weekStart, DateTime(2026, 9, 28));

    final otherUserTasks = await firestore
        .collection('users')
        .doc('student-b')
        .collection('tasks')
        .get();
    expect(otherUserTasks.docs, isEmpty);
  });

  test('creates and completes reminders in Firestore', () async {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'student-a', email: 'student@example.com'),
    );
    final service = TaskService(FakeFirebaseFirestore(), auth);

    await service.saveReminder(subject: 'PSP', message: 'Repasar sockets');
    var reminders = await service.loadReminders();
    expect(reminders, hasLength(1));
    expect(reminders.single.completed, isFalse);

    await service.setReminderCompleted(reminders.single.id, true);
    reminders = await service.loadReminders();
    expect(reminders.single.completed, isTrue);
  });
}