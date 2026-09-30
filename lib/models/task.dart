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
  });

  final String id;
  final String day;
  final String subject;
  final String message;
  final String color;
  final DateTime weekStart;
  final bool isExam;
  final bool completed;

  factory TaskItem.fromMap(Map<String, dynamic> map) => TaskItem(
        id: map['id'] as String,
        day: map['day'] as String,
        subject: map['subject'] as String,
        message: map['message'] as String,
        color: map['color'] as String? ?? '#2787A0',
        weekStart: DateTime.parse(map['week_start'] as String),
        isExam: map['is_exam'] as bool? ?? false,
        completed: map['completed'] as bool? ?? false,
      );
}

class ReminderItem {
  const ReminderItem({
    required this.id,
    required this.subject,
    required this.message,
    required this.completed,
  });

  final String id;
  final String subject;
  final String message;
  final bool completed;

  factory ReminderItem.fromMap(Map<String, dynamic> map) => ReminderItem(
        id: map['id'] as String,
        subject: map['subject'] as String,
        message: map['message'] as String,
        completed: map['completed'] as bool? ?? false,
      );
}