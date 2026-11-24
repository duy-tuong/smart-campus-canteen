import 'package:campus_canteen/data/firebase/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import '../support/fake_realtime.dart';

/// Rà responsive tự động: mở MỌI tab (và các màn con chính) của cả 3 vai trò ở nhiều kích thước màn hình,
/// kết hợp cỡ chữ lớn và giao diện tối. Flutter báo lỗi tràn (RenderFlex overflowed…) như một exception
/// → bố cục vỡ ở đâu thì test hỏng ở đó.
void main() {
  late AppHarness app;

  setUp(() async => app = await AppHarness.create());

  const staff = AuthUser(uid: 'uid-staff', email: 'staff@smartcanteen.vn');
  const admin = AuthUser(uid: 'uid-admin', email: 'admin@smartcanteen.vn');

  const cases = <(String, Size, double, Brightness)>[
    ('điện thoại nhỏ 320×640, chữ 130%', Size(320, 640), 1.3, Brightness.light),
    ('điện thoại ngang 780×360, tối', Size(780, 360), 1.0, Brightness.dark),
    ('tablet dọc 800×1280, chữ 130%, tối', Size(800, 1280), 1.3, Brightness.dark),
    ('tablet ngang 1280×800', Size(1280, 800), 1.0, Brightness.light),
    ('màn rộng 1600×1000, tối', Size(1600, 1000), 1.0, Brightness.dark),
  ];

  final nav = find.byWidgetPredicate((w) => w is NavigationBar || w is NavigationRail);

  Future<void> settle(WidgetTester tester) async {
    // Snackbar / skeleton chạy lặp → bơm đủ thời gian rồi mới settle.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(of: nav, matching: find.text(label)).first);
    await settle(tester);
  }

  /// Mở một màn con (bấm [target]) rồi quay lại.
  Future<void> visit(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target.first);
    await tester.pumpAndSettle();
    await tester.tap(target.first);
    await settle(tester);
    await tester.tap(find.byType(BackButton).first);
    await settle(tester);
  }

  Future<void> pumpAs(WidgetTester tester, AuthUser user, (String, Size, double, Brightness) c) async {
    tester.platformDispatcher.textScaleFactorTestValue = c.$3;
    tester.platformDispatcher.platformBrightnessTestValue = c.$4;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await app.pump(tester, signedIn: user, size: c.$2);
    await settle(tester);
  }

  for (final c in cases) {
    group(c.$1, () {
      testWidgets('sinh viên: thực đơn, chi tiết món, giỏ, đơn hàng, thông báo, tài khoản', (tester) async {
        final order = app.backend.seedOrder(status: 'cooking');
        app.realtime.pushOrder(
          liveOrder(order['id']! as String, status: 'cooking', pickupCode: order['pickupCode']! as String),
        );
        app.realtime.pushNotifications([notification(1, orderId: order['id']! as String), notification(2)]);
        await pumpAs(tester, AppHarness.student, c);

        await visit(tester, find.text('Cơm gà xối mỡ'));
        for (final tab in ['Giỏ hàng', 'Đơn hàng', 'Thông báo', 'Tài khoản', 'Thực đơn']) {
          await openTab(tester, tab);
        }
      });

      testWidgets('nhân viên: bảng đơn, quản lý (4 màn con), thống kê, tài khoản', (tester) async {
        for (final status in ['received', 'cooking', 'ready']) {
          final order = app.backend.seedOrder(status: status);
          app.realtime.pushOrder(
            liveOrder(order['id']! as String, status: status, pickupCode: order['pickupCode']! as String),
          );
        }
        await pumpAs(tester, staff, c);

        await openTab(tester, 'Quản lý');
        for (final screen in ['Thực đơn', 'Danh mục', 'Voucher', 'Đánh giá']) {
          await visit(tester, find.text(screen));
        }
        await openTab(tester, 'Thống kê');
        await openTab(tester, 'Tài khoản');
      });

      testWidgets('quản trị: người dùng + chi tiết tài khoản', (tester) async {
        await pumpAs(tester, admin, c);
        await openTab(tester, 'Người dùng');
        await visit(tester, find.textContaining('sv01@smartcanteen.vn'));
      });
    });
  }
}
