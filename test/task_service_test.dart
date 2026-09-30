import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:taskdam/data/schedule.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskdam/models/schedule_class.dart';
import 'package:taskdam/services/task_service.dart';

void main() {
  test('schedule is complete only when all thirty cells are assigned', () {
    const subject = ClassSubject(
      id: 'subject-a',
      name: 'Programación',
      teacher: 'Lucía',
      color: '#2787A0',
    );
    final cells = {
      for (final day in weekdays)
        for (var period = 0; period < 6; period++)
          '${day}_$period': subject.id,
    };
    final completeClass = ScheduleClass(
      id: 'class-a',
      name: '2º DAM',
      hasSchedule: true,
      subjects: const [subject],
      cells: cells,
    );
    expect(completeClass.isComplete, isTrue);

    final incompleteCells = Map<String, String>.from(cells)
      ..remove('Miércoles_2');
    final incompleteClass = ScheduleClass(
      id: completeClass.id,
      name: completeClass.name,
      hasSchedule: true,
      subjects: completeClass.subjects,
      cells: incompleteCells,
    );
    expect(incompleteClass.isComplete, isFalse);
  });

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
      scheduleId: 'dam-2',
    );

    final tasks = await service.loadTasks();
    expect(tasks, hasLength(1));
    expect(tasks.single.subject, 'IP2');
    expect(tasks.single.weekStart, DateTime(2026, 9, 28));
    expect(tasks.single.scheduleId, 'dam-2');

    final otherUserTasks = await firestore
        .collection('users')
        .doc('student-b')
        .collection('tasks')
        .get();
    expect(otherUserTasks.docs, isEmpty);
  });

  test('creates a class schedule and moves or clears its cells', () async {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'student-a', email: 'student@example.com'),
    );
    final service = TaskService(FakeFirebaseFirestore(), auth);

    final classId = await service.createClass('2º DAM');
    expect((await service.loadClasses()).single.hasSchedule, isFalse);
    await service.renameClass(classId, '2º DAM tarde');
    expect((await service.loadClasses()).single.name, '2º DAM tarde');

    await service.createSchedule(classId);
    final subjectId = await service.saveSubject(
      classId: classId,
      name: 'Programación',
      teacher: 'Lucía',
      color: '#2787A0',
    );
    final secondSubjectId = await service.saveSubject(
      classId: classId,
      name: 'Bases de datos',
      teacher: 'Marcos',
      color: '#59666A',
    );
    await service.setScheduleCell(
      classId: classId,
      day: 'Lunes',
      period: 0,
      subjectId: subjectId,
    );
    await service.setScheduleCell(
      classId: classId,
      day: 'Martes',
      period: 2,
      subjectId: secondSubjectId,
    );

    await service.moveScheduleCell(
      classId: classId,
      fromDay: 'Lunes',
      fromPeriod: 0,
      toDay: 'Martes',
      toPeriod: 2,
      subjectId: subjectId,
      destinationSubjectId: secondSubjectId,
    );
    var savedClass = (await service.loadClasses()).single;
    expect(savedClass.hasSchedule, isTrue);
    expect(savedClass.subjects, hasLength(2));
    expect(savedClass.cells['Lunes_0'], secondSubjectId);
    expect(savedClass.cells['Martes_2'], subjectId);

    await service.moveScheduleCell(
      classId: classId,
      fromDay: 'Lunes',
      fromPeriod: 0,
      toDay: 'Miércoles',
      toPeriod: 1,
      subjectId: secondSubjectId,
      destinationSubjectId: null,
    );
    savedClass = (await service.loadClasses()).single;
    expect(savedClass.cells.containsKey('Lunes_0'), isFalse);
    expect(savedClass.cells['Miércoles_1'], secondSubjectId);

    await service.setScheduleCell(
      classId: classId,
      day: 'Miércoles',
      period: 1,
      subjectId: null,
    );
    await service.setScheduleCell(
      classId: classId,
      day: 'Martes',
      period: 2,
      subjectId: null,
    );
    expect((await service.loadClasses()).single.cells, isEmpty);
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