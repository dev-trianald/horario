import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskdam/screens/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop creates a class and keeps the weekly dashboard',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Mis clases'), findsNWidgets(2));
    await _createClassAndSchedule(tester);

    expect(find.text('Pendientes'), findsOneWidget);
    expect(find.text('Por recordar'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Crear asignatura'), findsOneWidget);
    expect(find.text('Editar horario'), findsOneWidget);
    for (final day in ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes']) {
      expect(find.text(day), findsOneWidget);
    }
    expect(find.text('RECREO'), findsOneWidget);
  });

  testWidgets('desktop adds a subject to an empty timetable cell',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _createClassAndSchedule(tester);

    await tester.tap(find.text('Crear asignatura'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Programación');
    await tester.enterText(find.byType(TextFormField).at(1), 'Lucía');
    await tester.tap(find.widgetWithText(FilledButton, 'Añadir asignatura'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('schedule-cell-Lunes-0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('schedule-cell-Lunes-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Programación').last);
    await tester.pumpAndSettle();

    expect(find.text('Programación'), findsOneWidget);
    expect(find.text('Lucía'), findsOneWidget);
  });

  testWidgets('renames the selected class from its title action',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _createClassAndSchedule(tester);

    await tester.tap(find.byTooltip('Editar nombre de la clase'));
    await tester.pumpAndSettle();
    expect(find.text('2º DAM'), findsWidgets);
    await tester.enterText(find.byType(TextFormField).first, '2º DAM tarde');
    await tester.tap(find.text('Guardar nombre'));
    await tester.pumpAndSettle();

    expect(find.text('2º DAM tarde'), findsWidgets);
  });

  testWidgets('mobile keeps day selection and bottom navigation',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _createClassAndSchedule(tester);

    expect(find.byType(ChoiceChip), findsNWidgets(5));
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.text('Lunes'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('schedule-cell-Lunes-0')), findsOneWidget);
    expect(find.text('Crear asignatura'), findsOneWidget);
  });
}

Widget _app() => MaterialApp(
      home: HomeScreen(
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'student-a', email: 'student@example.com'),
        ),
        firestore: FakeFirebaseFirestore(),
      ),
    );

Future<void> _createClassAndSchedule(WidgetTester tester) async {
  final createLabel = tester.view.physicalSize.width < 600
      ? 'Añadir horario'
      : 'Crear clase';
  await tester.tap(find.text(createLabel).first);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).first, '2º DAM');
  await tester.tap(find.widgetWithText(FilledButton, 'Crear clase').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Crear horario').last);
  await tester.pumpAndSettle();
}
