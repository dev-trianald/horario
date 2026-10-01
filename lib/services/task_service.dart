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
      if (!document.exists) {
        final legacyData = membership.data();
        if (!legacyData.containsKey('name')) return null;
        return ScheduleClass.fromMap({...legacyData, 'id': membership.id});
      }
      return ScheduleClass.fromMap({...document.data()!, 'id': document.id});
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
      final memberDocument =
          _sharedClass(classId!).collection('members').doc(_userId);
      final membershipSnapshot = await transaction.get(membership);
      final memberSnapshot = await transaction.get(memberDocument);
      if (!membershipSnapshot.exists) {
        transaction.set(membership, {
          'access_code': normalizedCode,
          'created_at': FieldValue.serverTimestamp(),
        });
      }
      if (!memberSnapshot.exists) {
        transaction.set(memberDocument, {
          'display_name': _memberName,
          'created_at': FieldValue.serverTimestamp(),
        });
      }
    });
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
    final memberCollection = _sharedClass(classId).collection('members');
    final ownMember = memberCollection.doc(_userId);
    if (!(await ownMember.get()).exists) {
      final membership = await _userCollection('classes').doc(classId).get();
      if (membership.data()?['access_code'] is String) {
        await ownMember.set({
          'display_name': _memberName,
          'created_at': FieldValue.serverTimestamp(),
        });
      }
    }
    final snapshot = await memberCollection.orderBy('display_name').get();
    return snapshot.docs
        .map((document) => ClassMember(
              id: document.id,
              name: document.data()['display_name'] as String? ??
                  'Usuario ${document.id.substring(0, 6)}',
            ))
        .toList();
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
    await (await _classDocument(classId)).update({
      'has_schedule': true,
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
    final classDocument = await _classDocument(classId);
    final subjectId = classDocument
        .collection(
          'subjectIds',
        )
        .doc()
        .id;
    await classDocument.update({
      'subjects': FieldValue.arrayUnion([
        {
          'id': subjectId,
          'name': name,
          'teacher': teacher,
          'color': color,
        }
      ]),
    });
    return subjectId;
  }

  Future<void> setScheduleCell({
    required String classId,
    required String day,
    required int period,
    required String? subjectId,
  }) async {
    await (await _classDocument(classId)).update({
      'cells.${day}_$period': subjectId ?? FieldValue.delete(),
    });
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
    await (await _classDocument(classId)).update({
      'cells.${fromDay}_$fromPeriod':
          destinationSubjectId ?? FieldValue.delete(),
      'cells.${toDay}_$toPeriod': subjectId,
    });
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
