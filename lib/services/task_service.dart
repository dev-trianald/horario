import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/schedule.dart';
import '../models/schedule_class.dart';
import '../models/task.dart';

class TaskService {
  TaskService(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> _userCollection(String name) {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Inicia sesión para acceder a tus datos.');
    return _firestore.collection('users').doc(user.uid).collection(name);
  }

  Future<List<ScheduleClass>> loadClasses() async {
    final snapshot = await _userCollection('classes')
        .orderBy('created_at', descending: true)
        .get();
    return snapshot.docs
        .map((document) => ScheduleClass.fromMap({
              ...document.data(),
              'id': document.id,
            }))
        .toList();
  }

  Future<String> createClass(String name) async {
    final document = await _userCollection('classes').add({
      'name': name,
      'has_schedule': false,
      'subjects': <Map<String, dynamic>>[],
      'cells': <String, String>{},
      'created_at': FieldValue.serverTimestamp(),
    });
    return document.id;
  }

  Future<void> renameClass(String classId, String name) async {
    await _userCollection('classes').doc(classId).update({'name': name});
  }

  Future<void> createSchedule(String classId) async {
    await _userCollection('classes').doc(classId).update({
      'has_schedule': true,
    });
  }

  Future<String> saveSubject({
    required String classId,
    required String name,
    required String teacher,
    required String color,
  }) async {
    final subjectId = _userCollection('classes').doc(classId).collection(
      'subjectIds',
    ).doc().id;
    await _userCollection('classes').doc(classId).update({
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
    await _userCollection('classes').doc(classId).update({
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
    await _userCollection('classes').doc(classId).update({
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

  Future<void> saveTask({
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
      await collection.add(values);
    } else {
      await collection.doc(id).update(values);
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
  }) async {
    final collection = _userCollection('reminders');
    final values = <String, dynamic>{
      'subject': subject,
      'message': message,
    };
    if (id == null) {
      values['completed'] = false;
      values['created_at'] = FieldValue.serverTimestamp();
      await collection.add(values);
    } else {
      await collection.doc(id).update(values);
    }
  }

  Future<void> setReminderCompleted(String id, bool completed) async {
    await _userCollection('reminders')
        .doc(id)
        .update({'completed': completed});
  }

  Future<void> deleteReminder(String id) async {
    await _userCollection('reminders').doc(id).delete();
  }
}