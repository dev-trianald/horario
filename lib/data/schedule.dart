import 'package:flutter/material.dart';

const weekdays = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes'];
const subjects = ['IP2', 'PSP', 'SGE', 'PMDM', 'PI', 'DI', 'ING', 'AD', 'LD'];
const classTimes = [
  '8:15 - 9:15',
  '9:15 - 10:15',
  '10:15 - 11:15',
  '11:45 - 12:45',
  '12:45 - 13:45',
  '13:45 - 14:45',
];

const subjectColors = <String, Color>{
  'IP2': Color(0xFF555555),
  'PSP': Color(0xFF2980B9),
  'SGE': Color(0xFF27AE60),
  'PMDM': Color(0xFF8E44AD),
  'PI': Color(0xFF16A085),
  'DI': Color(0xFFD35400),
  'ING': Color(0xFFB7950B),
  'AD': Color(0xFF2C3E50),
  'LD': Color(0xFF3A536C),
};

const teachers = <String, String>{
  'IP2': 'Lourdes',
  'PSP': 'Daniel',
  'SGE': 'Rafa',
  'PMDM': 'Eva',
  'PI': 'Eva',
  'DI': 'Jacobo',
  'ING': 'Pablo',
  'AD': 'Fernando',
  'LD': 'Fernando',
};

const scheduleByDay = <String, List<String>>{
  'Lunes': ['IP2', 'PSP', 'PSP', 'SGE', 'SGE', 'PMDM'],
  'Martes': ['PI', 'PI', 'DI', 'DI', 'LD', 'AD'],
  'Miércoles': ['DI', 'DI', 'PMDM', 'IP2', 'LD', 'AD'],
  'Jueves': ['SGE', 'SGE', 'ING', 'PMDM', 'AD', 'DI'],
  'Viernes': ['PSP', 'DI', 'ING', 'IP2', 'LD', 'AD'],
};

DateTime mondayOf(DateTime date) {
  final localDate = DateTime(date.year, date.month, date.day);
  return localDate.subtract(Duration(days: localDate.weekday - DateTime.monday));
}

String dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';