import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskdam/services/task_service.dart';
import 'package:taskdam/screens/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('signed-out class home opens social sign-in options',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        auth: MockFirebaseAuth(),
        firestore: FakeFirebaseFirestore(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.textContaining('Google o correo'), findsOneWidget);
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(find.text('o con correo electrónico'), findsOneWidget);
  });

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

  testWidgets('joins a class from the search flow using its access code',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final firestore = FakeFirebaseFirestore();
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        key: const ValueKey('student-account'),
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'creator', email: 'creator@example.com'),
        ),
        firestore: firestore,
      ),
    ));
    await tester.pumpAndSettle();
    await _createClassAndSchedule(tester);

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'student', email: 'student@example.com'),
        ),
        firestore: firestore,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buscar una clase'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'dam2026');
    await tester.tap(find.widgetWithText(FilledButton, 'Buscar clase'));
    await tester.pumpAndSettle();

    expect(find.text('2º DAM'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('class users can view a member tasks and reminders read-only',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final firestore = FakeFirebaseFirestore();
    final owner = TaskService(
      firestore,
      MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'class-owner', email: 'owner@example.com'),
      ),
    );
    final classId = await owner.createClass('2º DAM', 'DAM2026');
    await owner.saveTask(
      day: 'Lunes',
      subject: 'Programación',
      message: 'Apunte para compartir',
      color: '#2787A0',
      weekStart: DateTime(2026, 9, 28),
      isExam: false,
      scheduleId: classId,
    );
    await owner.saveReminder(
      subject: 'Programación',
      message: 'Recordatorio compartido',
      scheduleId: classId,
    );
    final viewerAuth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'class-viewer', email: 'viewer@example.com'),
    );
    await TaskService(firestore, viewerAuth).joinClass('DAM2026');

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(auth: viewerAuth, firestore: firestore),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2º DAM').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuarios'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('owner'));
    await tester.pumpAndSettle();

    final sharedTask = find.textContaining('Apunte para compartir');
    expect(sharedTask, findsOneWidget);
    expect(find.text('Recordatorio compartido'), findsOneWidget);
    final taskCard = find.ancestor(
      of: sharedTask,
      matching: find.byType(Card),
    );
    final reminderCard = find.ancestor(
      of: find.text('Recordatorio compartido'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: taskCard, matching: find.byType(IconButton)),
      findsNothing,
    );
    expect(
      find.descendant(of: reminderCard, matching: find.byType(IconButton)),
      findsNothing,
    );
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

  testWidgets('creates a class from an existing schedule', (tester) async {
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

    await tester.tap(find.byTooltip('Volver a mis clases'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crear clase').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '2º DAM tarde');
    await tester.enterText(find.byType(TextFormField).at(1), 'TARDE26');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2º DAM').last);
    final saveButton = find.widgetWithText(FilledButton, 'Crear clase').last;
    tester.widget<FilledButton>(saveButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('2º DAM tarde'), findsWidgets);
    expect(find.text('Aún no hay horario'), findsNothing);
  });

  testWidgets('deletes a class after confirmation', (tester) async {
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

    await tester.tap(find.byTooltip('Volver a mis clases'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Salir de la clase'));
    await tester.pumpAndSettle();

    expect(find.text('¿Salir de "2º DAM"?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Salir'));
    await tester.pumpAndSettle();

    expect(find.text('Aún no has creado ninguna clase.'), findsOneWidget);
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
  await tester.tap(find.text('Crear clase').first);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).first, '2º DAM');
  await tester.enterText(find.byType(TextFormField).at(1), 'DAM2026');
  final saveButton = find.widgetWithText(FilledButton, 'Crear clase').last;
  await tester.ensureVisible(saveButton);
  await tester.tap(saveButton);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Crear horario').last);
  await tester.pumpAndSettle();
}
