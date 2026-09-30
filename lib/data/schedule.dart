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
  'IP2': Color(0xFF59666A),
  'PSP': Color(0xFF247FA2),
  'SGE': Color(0xFF33875E),
  'PMDM': Color(0xFF9A5C3D),
  'PI': Color(0xFF238A7B),
  'DI': Color(0xFFC25F3B),
  'ING': Color(0xFFA17B24),
  'AD': Color(0xFF52667A),
  'LD': Color(0xFF657B88),
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