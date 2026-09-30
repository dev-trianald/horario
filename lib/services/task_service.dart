import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/schedule.dart';
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