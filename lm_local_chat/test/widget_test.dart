import 'package:flutter_test/flutter_test.dart';

import 'package:lm_local_chat/main.dart';

void main() {
  testWidgets('Orbit splash renders', (tester) async {
    await tester.pumpWidget(const OrbitApp());
    expect(find.text('orbit'), findsWidgets);
  });
}
