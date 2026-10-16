import 'package:flutter_test/flutter_test.dart';
import 'package:taskdam/models/task.dart';

void main() {
  test('sorts tasks by distance from today, then earlier date on a tie', () {
    final today = DateTime(2026, 10, 16);
    final tasks = [
      _task('far-future', DateTime(2026, 10, 31)),
      _task('tomorrow', DateTime(2026, 10, 17)),
      _task('yesterday', DateTime(2026, 10, 15)),
      _task('today', today),
      _task('far-past', DateTime(2026, 10, 1)),
    ];

    expect(
      tasksByDateProximity(tasks, referenceDate: today).map((task) => task.id),
      ['today', 'yesterday', 'tomorrow', 'far-past', 'far-future'],
    );
  });

  test('sorts reminders by most recent creation date', () {
    final reminders = [
      _reminder('older', DateTime(2026, 10, 10)),
      _reminder('newer', DateTime(2026, 10, 15)),
      _reminder('no-date', null),
    ];

    expect(
      remindersByCreationDate(reminders).map((reminder) => reminder.id),
      ['newer', 'older', 'no-date'],
    );
  });
}

TaskItem _task(String id, DateTime date) => TaskItem(
      id: id,
      day: const [
        'Lunes',
        'Martes',
        'Miércoles',
        'Jueves',
        'Viernes',
        'Sábado',
        'Domingo'
      ][date.weekday - 1],
      subject: 'Asignatura',
      message: id,
      color: '#2787A0',
      weekStart: DateTime(date.year, date.month, date.day)
          .subtract(Duration(days: date.weekday - 1)),
      isExam: false,
      completed: false,
    );

ReminderItem _reminder(String id, DateTime? createdAt) => ReminderItem(
      id: id,
      subject: 'Asignatura',
      message: id,
      completed: false,
      createdAt: createdAt,
    );
