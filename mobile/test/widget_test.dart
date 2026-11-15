import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:campus_canteen/app.dart';

void main() {
  testWidgets('App khởi động và đổi được theme Sáng/Tối', (tester) async {
    await tester.pumpWidget(const CanteenApp());

    expect(find.text('Smart Canteen'), findsOneWidget);
    expect(find.byIcon(Icons.dark_mode), findsOneWidget);

    await tester.tap(find.byIcon(Icons.dark_mode));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.light_mode), findsOneWidget);
  });
}
