import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskdam/screens/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop shows the full week beside tasks and reminders',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await tester.pumpWidget(MaterialApp(home: HomeScreen(client: client)));
    await tester.pump();

    expect(
        MediaQuery.sizeOf(tester.element(find.byType(HomeScreen))).width, 1440);
    expect(find.text('Horario semanal'), findsOneWidget);
    expect(find.text('Tareas y exámenes'), findsOneWidget);
    expect(find.text('Recordatorios'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    for (final day in ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes']) {
      expect(find.text(day), findsOneWidget);
    }
    expect(find.text('RECREO'), findsOneWidget);
  });

  testWidgets('mobile keeps the day selector and bottom navigation',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await tester.pumpWidget(MaterialApp(home: HomeScreen(client: client)));
    await tester.pump();

    expect(find.byType(ChoiceChip), findsNWidgets(5));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Horario semanal'), findsNothing);
  });
}
