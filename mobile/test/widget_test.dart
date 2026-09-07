import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:uplink/main.dart';

void main() {
  testWidgets('shows login gate', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const UplinkApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Uplink'), findsOneWidget);
  });
}
