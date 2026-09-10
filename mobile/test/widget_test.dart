import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:uplink/main.dart';

void main() {
  testWidgets('opens workspace before any saved link', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const UplinkApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('创建连接'), findsOneWidget);
    expect(find.text('发消息'), findsOneWidget);
    expect(find.text('Agent'), findsOneWidget);
  });
}
