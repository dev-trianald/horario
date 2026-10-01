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
        for (var period = 0; period < 6; period++) '${day}_$period': subject.id,
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

  test('keeps existing per-user classes usable as private schedules', () async {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'student-a', email: 'student@example.com'),
    );
    final firestore = FakeFirebaseFirestore();
    final legacyClass = firestore
        .collection('users')
        .doc('student-a')
        .collection('classes')
        .doc('legacy-class');
    await legacyClass.set({
      'name': 'Horario anterior',
      'has_schedule': false,
      'subjects': <Map<String, dynamic>>[],
      'cells': <String, String>{},
      'created_at': DateTime(2025, 9, 1),
    });
    final service = TaskService(firestore, auth);

    expect((await service.loadClasses()).single.name, 'Horario anterior');
    await service.createSchedule('legacy-class');
    await service.renameClass('legacy-class', 'Horario actualizado');

    final saved = await legacyClass.get();
    expect(saved.data()?['has_schedule'], isTrue);
    expect(saved.data()?['name'], 'Horario actualizado');
    expect(
      (await firestore.collection('classes').doc('legacy-class').get()).exists,
      isFalse,
    );
  });

  test('creates a class schedule and moves or clears its cells', () async {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'student-a', email: 'student@example.com'),
    );
    final service = TaskService(FakeFirebaseFirestore(), auth);

    final classId = await service.createClass('2º DAM', 'DAM2026');
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

  test('creates a new class with a copy of an existing schedule', () async {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'student-a', email: 'student@example.com'),
    );
    final service = TaskService(FakeFirebaseFirestore(), auth);
    final originalId = await service.createClass('Horario original', 'ORIGEN');
    await service.createSchedule(originalId);
    final subjectId = await service.saveSubject(
      classId: originalId,
      name: 'Programación',
      teacher: 'Lucía',
      color: '#2787A0',
    );
    await service.setScheduleCell(
      classId: originalId,
      day: 'Lunes',
      period: 0,
      subjectId: subjectId,
    );
    final original = (await service.loadClasses()).single;

    final copiedId = await service.createClass(
      'Horario copiado',
      'COPIADO',
      scheduleTemplate: original,
    );
    final classes = await service.loadClasses();
    final copied = classes.singleWhere((item) => item.id == copiedId);

    expect(copied.id, isNot(original.id));
    expect(copied.name, 'Horario copiado');
    expect(copied.hasSchedule, isTrue);
    expect(copied.subjects.single.name, 'Programación');
    expect(copied.cells['Lunes_0'], subjectId);
  });

  test('deletes a class from the signed-in user collection', () async {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'student-a', email: 'student@example.com'),
    );
    final service = TaskService(FakeFirebaseFirestore(), auth);
    final classId = await service.createClass('2º DAM', 'DAM2026');

    await service.deleteClass(classId);

    expect(await service.loadClasses(), isEmpty);
  });

  test('joins shared schedules while keeping tasks private per user', () async {
    final firestore = FakeFirebaseFirestore();
    final creatorAuth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'creator', email: 'creator@example.com'),
    );
    final creator = TaskService(firestore, creatorAuth);
    final classId = await creator.createClass('2º DAM', 'DAM2026');
    await creator.createSchedule(classId);
    final subjectId = await creator.saveSubject(
      classId: classId,
      name: 'Programación',
      teacher: 'Lucía',
      color: '#2787A0',
    );
    await creator.setScheduleCell(
      classId: classId,
      day: 'Lunes',
      period: 0,
      subjectId: subjectId,
    );
    await creator.saveTask(
      day: 'Lunes',
      subject: 'Programación',
      message: 'Solo para mí',
      color: '#2787A0',
      weekStart: DateTime(2026, 9, 28),
      isExam: false,
      scheduleId: classId,
    );
    await creator.saveReminder(
      subject: 'Programación',
      message: 'Traer el portátil',
      scheduleId: classId,
    );

    final studentAuth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'student', email: 'student@example.com'),
    );
    final student = TaskService(firestore, studentAuth);
    expect(await student.joinClass(' dam2026 '), classId);
    final joinedClass = (await student.loadClasses()).single;
    expect(joinedClass.name, '2º DAM');
    expect(joinedClass.cells['Lunes_0'], subjectId);
    expect(await student.loadTasks(), isEmpty);
    expect(
      (await student.loadClassMembers(classId)).map((member) => member.id),
      containsAll(['creator', 'student']),
    );
    expect(
      (await student.loadMemberTasks(classId: classId, memberId: 'creator'))
          .single
          .message,
      'Solo para mí',
    );
    expect(
      (await student.loadMemberReminders(classId: classId, memberId: 'creator'))
          .single
          .message,
      'Traer el portátil',
    );
    expect(
      await student.loadMemberReminders(
          classId: 'another-class', memberId: 'creator'),
      isEmpty,
    );
    expect(
      await student.loadMemberTasks(
          classId: 'another-class', memberId: 'creator'),
      isEmpty,
    );

    await student.saveTask(
      day: 'Martes',
      subject: 'Programación',
      message: 'Tarea privada',
      color: '#2787A0',
      weekStart: DateTime(2026, 9, 28),
      isExam: false,
      scheduleId: classId,
    );
    expect((await creator.loadTasks()).single.message, 'Solo para mí');
    expect((await student.loadTasks()).single.message, 'Tarea privada');
  });

  test('registers existing class members when they open the member list',
      () async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'existing-user', email: 'existing@example.com'),
    );
    final service = TaskService(firestore, auth);
    final classId = await service.createClass('2º DAM', 'DAM2026');
    await firestore
        .collection('classes')
        .doc(classId)
        .collection('members')
        .doc('existing-user')
        .delete();

    final members = await service.loadClassMembers(classId);

    expect(members.map((member) => member.id), contains('existing-user'));
  });

  test('rejects duplicate class access codes', () async {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'student-a', email: 'student@example.com'),
    );
    final service = TaskService(FakeFirebaseFirestore(), auth);
    await service.createClass('2º DAM', 'DAM2026');

    await expectLater(
      service.createClass('Otra clase', 'dam2026'),
      throwsA(isA<StateError>()),
    );
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
