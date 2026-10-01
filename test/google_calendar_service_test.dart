import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskdam/services/google_calendar_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Firebase sign-out pause does not clear the Calendar preference',
      () async {
    SharedPreferences.setMockInitialValues({
      'google_calendar_keep_connected': true,
    });
    final service = GoogleCalendarService();

    service.pauseForFirebaseSignOut();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('google_calendar_keep_connected'), isTrue);
  });

  test('explicit Calendar disconnect clears the remembered preference',
      () async {
    SharedPreferences.setMockInitialValues({
      'google_calendar_keep_connected': true,
    });
    final service = GoogleCalendarService();

    await service.disconnect();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('google_calendar_keep_connected'), isNull);
    expect(service.shouldStayConnected, isFalse);
  });

  test('restore remains disabled until Calendar was explicitly connected',
      () async {
    SharedPreferences.setMockInitialValues({});
    final service = GoogleCalendarService();

    expect(await service.restore('student@example.com'), isFalse);
    expect(service.shouldStayConnected, isFalse);
  });
}
