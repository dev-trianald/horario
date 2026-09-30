import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/schedule.dart';
import '../models/task.dart';

class TaskService {
  TaskService(this._client);

  final SupabaseClient _client;

  Future<List<TaskItem>> loadTasks() async {
    final rows = await _client
        .from('tasks')
        .select('id, day, subject, message, color, week_start, is_exam, completed')
        .order('created_at', ascending: false);
    return (rows as List)
        .map((row) => TaskItem.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<List<ReminderItem>> loadReminders() async {
    final rows = await _client
        .from('reminders')
        .select('id, subject, message, completed')
        .order('created_at', ascending: false);
    return (rows as List)
        .map((row) => ReminderItem.fromMap(Map<String, dynamic>.from(row)))
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
    final values = {
      'day': day,
      'subject': subject,
      'message': message,
      'color': color,
      'week_start': dateKey(weekStart),
      'is_exam': isExam,
    };
    if (id == null) {
      await _client.from('tasks').insert(values);
    } else {
      await _client.from('tasks').update(values).eq('id', id);
    }
  }

  Future<void> setTaskCompleted(String id, bool completed) async {
    await _client.from('tasks').update({'completed': completed}).eq('id', id);
  }

  Future<void> deleteTask(String id) async {
    await _client.from('tasks').delete().eq('id', id);
  }

  Future<void> saveReminder({
    String? id,
    required String subject,
    required String message,
  }) async {
    final values = {'subject': subject, 'message': message};
    if (id == null) {
      await _client.from('reminders').insert(values);
    } else {
      await _client.from('reminders').update(values).eq('id', id);
    }
  }

  Future<void> setReminderCompleted(String id, bool completed) async {
    await _client
        .from('reminders')
        .update({'completed': completed})
        .eq('id', id);
  }

  Future<void> deleteReminder(String id) async {
    await _client.from('reminders').delete().eq('id', id);
  }
}