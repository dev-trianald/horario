import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/schedule.dart';
import '../models/schedule_class.dart';
import '../models/task.dart';

class TaskService {
  TaskService(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String get _userId {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Inicia sesión para acceder a tus datos.');
    }
    return user.uid;
  }

  String get _memberName {
    final user = _auth.currentUser!;
    final displayName = user.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    final emailName = user.email?.split('@').first;
    if (emailName != null && emailName.isNotEmpty) return emailName;
    return 'Usuario ${user.uid.substring(0, 6)}';
  }

  CollectionReference<Map<String, dynamic>> _userCollection(String name) {
    return _firestore.collection('users').doc(_userId).collection(name);
  }

  Future<List<ScheduleClass>> loadClasses() async {
    final memberships = await _userCollection('classes')
        .orderBy('created_at', descending: true)
        .get();
    final classes = await Future.wait(memberships.docs.map((membership) async {
      final document =
          await _firestore.collection('classes').doc(membership.id).get();
      final membershipData = membership.data();
      if (!document.exists) {
        if (!membershipData.containsKey('name')) return null;
        return ScheduleClass.fromMap({...membershipData, 'id': membership.id});
      }
      final classData = Map<String, dynamic>.from(document.data()!);
      for (final field in ['has_schedule', 'subjects', 'cells', 'times']) {
        if (membershipData.containsKey(field)) {
          classData[field] = membershipData[field];
        }
      }
      return ScheduleClass.fromMap({...classData, 'id': document.id});
    }));
    return classes.whereType<ScheduleClass>().toList();
  }

  Future<String> createClass(String name, String accessCode,
      {ScheduleClass? scheduleTemplate}) async {
    final normalizedCode = _normalizeAccessCode(accessCode);
    if (!RegExp(r'^[A-Z0-9]{6,12}$').hasMatch(normalizedCode)) {
      throw ArgumentError(
          'El código debe tener entre 6 y 12 letras o números.');
    }
    final classDocument = _firestore.collection('classes').doc();
    final codeDocument =
        _firestore.collection('class_codes').doc(normalizedCode);
    final membershipDocument = _userCollection('classes').doc(classDocument.id);

    await _firestore.runTransaction((transaction) async {
      final existingCode = await transaction.get(codeDocument);
      if (existingCode.exists) {
        throw StateError('Ese código ya está en uso. Elige otro.');
      }
      transaction.set(classDocument, {
        'name': name,
        'access_code': normalizedCode,
        'owner_id': _userId,
        'has_schedule': scheduleTemplate?.hasSchedule ?? false,
        'subjects': scheduleTemplate?.subjects
                .map((subject) => subject.toMap())
                .toList() ??
            <Map<String, dynamic>>[],
        'cells': scheduleTemplate?.cells ?? <String, String>{},
        'times': scheduleTemplate?.times ?? classTimes,
        'created_at': FieldValue.serverTimestamp(),
      });
      transaction.set(codeDocument, {
        'class_id': classDocument.id,
        'created_by': _userId,
        'created_at': FieldValue.serverTimestamp(),
      });
      transaction.set(membershipDocument, {
        'access_code': normalizedCode,
        'created_at': FieldValue.serverTimestamp(),
      });
      transaction.set(classDocument.collection('members').doc(_userId), {
        'display_name': _memberName,
        'created_at': FieldValue.serverTimestamp(),
      });
    });
    return classDocument.id;
  }

  Future<String> joinClass(String accessCode) async {
    final normalizedCode = _normalizeAccessCode(accessCode);
    if (!RegExp(r'^[A-Z0-9]{6,12}$').hasMatch(normalizedCode)) {
      throw ArgumentError(
          'El código debe tener entre 6 y 12 letras o números.');
    }
    final codeDocument =
        _firestore.collection('class_codes').doc(normalizedCode);
    String? classId;
    await _firestore.runTransaction((transaction) async {
      final code = await transaction.get(codeDocument);
      classId = code.data()?['class_id'] as String?;
      if (!code.exists || classId == null) {
        throw StateError('No se ha encontrado ninguna clase con ese código.');
      }
      final membership = _userCollection('classes').doc(classId);
      final membershipSnapshot = await transaction.get(membership);
      if (!membershipSnapshot.exists) {
        transaction.set(membership, {
          'access_code': normalizedCode,
          'created_at': FieldValue.serverTimestamp(),
        });
      }
    });
    await _ensureClassMember(classId!);
    return classId!;
  }

  Future<void> renameClass(String classId, String name) async {
    await (await _classDocument(classId)).update({'name': name});
  }

  Future<void> deleteClass(String classId) async {
    final batch = _firestore.batch();
    batch.delete(_userCollection('classes').doc(classId));
    batch.delete(_sharedClass(classId).collection('members').doc(_userId));
    await batch.commit();
  }

  Future<List<ClassMember>> loadClassMembers(String classId) async {
    await _ensureClassMember(classId);
    final memberCollection = _sharedClass(classId).collection('members');
    final snapshot = await memberCollection.orderBy('display_name').get();
    return snapshot.docs
        .map((document) => ClassMember(
              id: document.id,
              name: document.data()['display_name'] as String? ??
                  'Usuario ${document.id.substring(0, 6)}',
            ))
        .toList();
  }

  Future<void> _ensureClassMember(String classId) async {
    final membership = await _userCollection('classes').doc(classId).get();
    if (membership.data()?['access_code'] is! String) return;
    final ownMember = _sharedClass(classId).collection('members').doc(_userId);
    if ((await ownMember.get()).exists) return;
    await ownMember.set({
      'display_name': _memberName,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  Future<List<TaskItem>> loadMemberTasks({
    required String classId,
    required String memberId,
  }) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(memberId)
        .collection('tasks')
        .where('schedule_id', isEqualTo: classId)
        .get();
    return snapshot.docs
        .map((document) => TaskItem.fromMap({
              ...document.data(),
              'id': document.id,
            }))
        .toList();
  }

  Future<List<ReminderItem>> loadMemberReminders({
    required String classId,
    required String memberId,
  }) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(memberId)
        .collection('reminders')
        .where('schedule_id', isEqualTo: classId)
        .get();
    return snapshot.docs
        .map((document) => ReminderItem.fromMap({
              ...document.data(),
              'id': document.id,
            }))
        .toList();
  }

  Future<void> createSchedule(String classId) async {
    final classItem = await _loadScheduleClass(classId);
    await _savePersonalSchedule(
      classId,
      hasSchedule: true,
      subjects: classItem.subjects,
      cells: classItem.cells,
      times: classItem.times,
    );
  }

  Future<ScheduleClass> _loadScheduleClass(String classId) async {
    for (final classItem in await loadClasses()) {
      if (classItem.id == classId) return classItem;
    }
    throw StateError('No se ha encontrado la clase seleccionada.');
  }

  Future<void> _savePersonalSchedule(
    String classId, {
    required bool hasSchedule,
    required List<ClassSubject> subjects,
    required Map<String, String> cells,
    required List<String> times,
  }) async {
    await _userCollection('classes').doc(classId).update({
      'has_schedule': hasSchedule,
      'subjects': subjects.map((subject) => subject.toMap()).toList(),
      'cells': cells,
      'times': times,
    });
  }

  Future<DocumentReference<Map<String, dynamic>>> _classDocument(
      String classId) async {
    final personalDocument = _userCollection('classes').doc(classId);
    final membership = await personalDocument.get();
    if (membership.data()?.containsKey('name') == true) {
      return personalDocument;
    }
    return _sharedClass(classId);
  }

  DocumentReference<Map<String, dynamic>> _sharedClass(String classId) =>
      _firestore.collection('classes').doc(classId);

  String _normalizeAccessCode(String value) => value.trim().toUpperCase();

  Future<String> saveSubject({
    required String classId,
    required String name,
    required String teacher,
    required String color,
  }) async {
    final classItem = await _loadScheduleClass(classId);
    final subjectId = _userCollection('classes')
        .doc(classId)
        .collection('subjectIds')
        .doc()
        .id;
    await _savePersonalSchedule(
      classId,
      hasSchedule: classItem.hasSchedule,
      subjects: [
        ...classItem.subjects,
        ClassSubject(
          id: subjectId,
          name: name,
          teacher: teacher,
          color: color,
        ),
      ],
      cells: classItem.cells,
      times: classItem.times,
    );
    return subjectId;
  }

  Future<void> updateSubject({
    required String classId,
    required String subjectId,
    required String name,
    required String teacher,
    required String color,
  }) async {
    final classItem = await _loadScheduleClass(classId);
    if (!classItem.subjects.any((subject) => subject.id == subjectId)) {
      throw StateError('No se ha encontrado la asignatura.');
    }
    final subjects = classItem.subjects
        .map((subject) => subject.id == subjectId
            ? ClassSubject(
                id: subject.id,
                name: name,
                teacher: teacher,
                color: color,
              )
            : subject)
        .toList();
    await _savePersonalSchedule(
      classId,
      hasSchedule: classItem.hasSchedule,
      subjects: subjects,
      cells: classItem.cells,
      times: classItem.times,
    );
  }

  Future<void> setScheduleCell({
    required String classId,
    required String day,
    required int period,
    required String? subjectId,
  }) async {
    final classItem = await _loadScheduleClass(classId);
    final cells = Map<String, String>.from(classItem.cells);
    final key = '${day}_$period';
    if (subjectId == null) {
      cells.remove(key);
    } else {
      cells[key] = subjectId;
    }
    await _savePersonalSchedule(
      classId,
      hasSchedule: classItem.hasSchedule,
      subjects: classItem.subjects,
      cells: cells,
      times: classItem.times,
    );
  }

  Future<void> moveScheduleCell({
    required String classId,
    required String fromDay,
    required int fromPeriod,
    required String toDay,
    required int toPeriod,
    required String subjectId,
    required String? destinationSubjectId,
  }) async {
    final classItem = await _loadScheduleClass(classId);
    final cells = Map<String, String>.from(classItem.cells);
    final fromKey = '${fromDay}_$fromPeriod';
    final toKey = '${toDay}_$toPeriod';
    if (destinationSubjectId == null) {
      cells.remove(fromKey);
    } else {
      cells[fromKey] = destinationSubjectId;
    }
    cells[toKey] = subjectId;
    await _savePersonalSchedule(
      classId,
      hasSchedule: classItem.hasSchedule,
      subjects: classItem.subjects,
      cells: cells,
      times: classItem.times,
    );
  }

  Future<void> updateScheduleTimes({
    required String classId,
    required List<String> times,
  }) async {
    if (times.length != classTimes.length) {
      throw ArgumentError('El horario debe tener ${classTimes.length} tramos.');
    }
    final classItem = await _loadScheduleClass(classId);
    await _savePersonalSchedule(
      classId,
      hasSchedule: classItem.hasSchedule,
      subjects: classItem.subjects,
      cells: classItem.cells,
      times: times,
    );
  }

  Future<List<TaskItem>> loadTasks() async {
    final snapshot = await _userCollection('tasks')
        .orderBy('created_at', descending: true)
        .get();
    return snapshot.docs
        .map((document) => TaskItem.fromMap({
              ...document.data(),
              'id': document.id,
            }))
        .toList();
  }

  Future<List<ReminderItem>> loadReminders() async {
    final snapshot = await _userCollection('reminders')
        .orderBy('created_at', descending: true)
        .get();
    return snapshot.docs
        .map((document) => ReminderItem.fromMap({
              ...document.data(),
              'id': document.id,
            }))
        .toList();
  }

  Future<String> saveTask({
    String? id,
    required String day,
    required String subject,
    required String message,
    required String color,
    required DateTime weekStart,
    required bool isExam,
    String? scheduleId,
  }) async {
    final collection = _userCollection('tasks');
    final values = <String, dynamic>{
      'day': day,
      'subject': subject,
      'message': message,
      'color': color,
      'week_start': dateKey(weekStart),
      'is_exam': isExam,
    };
    if (scheduleId != null) values['schedule_id'] = scheduleId;
    if (id == null) {
      values['completed'] = false;
      values['created_at'] = FieldValue.serverTimestamp();
      final document = await collection.add(values);
      return document.id;
    } else {
      await collection.doc(id).update(values);
      return id;
    }
  }

  Future<void> setTaskCompleted(String id, bool completed) async {
    await _userCollection('tasks').doc(id).update({'completed': completed});
  }

  Future<void> deleteTask(String id) async {
    await _userCollection('tasks').doc(id).delete();
  }

  Future<void> saveReminder({
    String? id,
    required String subject,
    required String message,
    String? scheduleId,
  }) async {
    final collection = _userCollection('reminders');
    final values = <String, dynamic>{
      'subject': subject,
      'message': message,
    };
    if (scheduleId != null) values['schedule_id'] = scheduleId;
    if (id == null) {
      values['completed'] = false;
      values['created_at'] = FieldValue.serverTimestamp();
      await collection.add(values);
    } else {
      await collection.doc(id).update(values);
    }
  }

  Future<void> setReminderCompleted(String id, bool completed) async {
    await _userCollection('reminders').doc(id).update({'completed': completed});
  }

  Future<void> deleteReminder(String id) async {
    await _userCollection('reminders').doc(id).delete();
  }
}
