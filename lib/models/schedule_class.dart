import '../data/schedule.dart';

class ClassSubject {
  const ClassSubject({
    required this.id,
    required this.name,
    required this.teacher,
    required this.color,
  });

  final String id;
  final String name;
  final String teacher;
  final String color;

  factory ClassSubject.fromMap(Map<String, dynamic> map) => ClassSubject(
        id: map['id'] as String,
        name: map['name'] as String,
        teacher: map['teacher'] as String,
        color: map['color'] as String,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'teacher': teacher,
        'color': color,
      };
}

class ScheduleClass {
  const ScheduleClass({
    required this.id,
    required this.name,
    required this.hasSchedule,
    required this.subjects,
    required this.cells,
    this.times = classTimes,
    this.accessCode = '',
  });

  final String id;
  final String name;
  final bool hasSchedule;
  final List<ClassSubject> subjects;
  final Map<String, String> cells;
  final List<String> times;
  final String accessCode;

  factory ScheduleClass.fromMap(Map<String, dynamic> map) => ScheduleClass(
        id: map['id'] as String,
        name: map['name'] as String,
        hasSchedule: map['has_schedule'] as bool? ?? false,
        subjects: (map['subjects'] as List<dynamic>? ?? const [])
            .map((subject) =>
                ClassSubject.fromMap(Map<String, dynamic>.from(subject as Map)))
            .toList(),
        cells: (map['cells'] as Map<String, dynamic>? ?? const {}).map(
          (key, value) => MapEntry(key, value as String),
        ),
        times: (map['times'] as List<dynamic>?)
                ?.map((time) => time as String)
                .toList() ??
            classTimes,
        accessCode: map['access_code'] as String? ?? '',
      );

  ClassSubject? subjectById(String? subjectId) {
    for (final subject in subjects) {
      if (subject.id == subjectId) return subject;
    }
    return null;
  }

  bool get isComplete =>
      hasSchedule &&
      weekdays.every((day) => List.generate(6, (period) => '${day}_$period')
          .every((key) => subjectById(cells[key]) != null));
}
