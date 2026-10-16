import '../data/schedule.dart';

DateTime taskDueDate(TaskItem task) {
  final weekdayIndex = calendarWeekdays.indexOf(task.day);
  if (weekdayIndex < 0) {
    throw StateError('No se reconoce el día de la tarea: ${task.day}.');
  }
  return mondayOf(task.weekStart).add(Duration(days: weekdayIndex));
}

List<TaskItem> tasksByDateProximity(
  Iterable<TaskItem> tasks, {
  DateTime? referenceDate,
}) {
  final today = referenceDate ?? DateTime.now();
  final todayDate = DateTime(today.year, today.month, today.day);
  final sorted = tasks.toList();
  sorted.sort((first, second) {
    final firstDate = taskDueDate(first);
    final secondDate = taskDueDate(second);
    final firstDistance = firstDate.difference(todayDate).inDays.abs();
    final secondDistance = secondDate.difference(todayDate).inDays.abs();
    final distanceOrder = firstDistance.compareTo(secondDistance);
    return distanceOrder != 0 ? distanceOrder : firstDate.compareTo(secondDate);
  });
  return sorted;
}

class ClassMember {
  const ClassMember({required this.id, required this.name});

  final String id;
  final String name;
}

class TaskItem {
  const TaskItem({
    required this.id,
    required this.day,
    required this.subject,
    required this.message,
    required this.color,
    required this.weekStart,
    required this.isExam,
    required this.completed,
    this.scheduleId,
  });

  final String id;
  final String day;
  final String subject;
  final String message;
  final String color;
  final DateTime weekStart;
  final bool isExam;
  final bool completed;
  final String? scheduleId;

  factory TaskItem.fromMap(Map<String, dynamic> map) => TaskItem(
        id: map['id'] as String,
        day: map['day'] as String,
        subject: map['subject'] as String,
        message: map['message'] as String,
        color: map['color'] as String? ?? '#2787A0',
        weekStart: DateTime.parse(map['week_start'] as String),
        isExam: map['is_exam'] as bool? ?? false,
        completed: map['completed'] as bool? ?? false,
        scheduleId: map['schedule_id'] as String?,
      );
}

class ReminderItem {
  const ReminderItem({
    required this.id,
    required this.subject,
    required this.message,
    required this.completed,
    this.createdAt,
  });

  final String id;
  final String subject;
  final String message;
  final bool completed;
  final DateTime? createdAt;

  factory ReminderItem.fromMap(Map<String, dynamic> map) => ReminderItem(
        id: map['id'] as String,
        subject: map['subject'] as String,
        message: map['message'] as String,
        completed: map['completed'] as bool? ?? false,
        createdAt: map['created_at'] as DateTime?,
      );
}

List<ReminderItem> remindersByCreationDate(Iterable<ReminderItem> reminders) {
  final sorted = reminders.toList();
  sorted.sort((first, second) {
    final firstDate = first.createdAt;
    final secondDate = second.createdAt;
    if (firstDate == null) return secondDate == null ? 0 : 1;
    if (secondDate == null) return -1;
    return secondDate.compareTo(firstDate);
  });
  return sorted;
}
