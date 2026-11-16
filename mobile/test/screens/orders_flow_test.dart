import 'dart:convert';

import 'package:campus_canteen/models/cart_item.dart';
import 'package:campus_canteen/models/enums.dart';
import 'package:campus_canteen/models/order.dart';
import 'package:campus_canteen/screens/checkout/order_placed_screen.dart';
import 'package:campus_canteen/screens/checkout/payment_screen.dart';
import 'package:campus_canteen/screens/notifications/notifications_screen.dart';
import 'package:campus_canteen/screens/orders/order_screen.dart';
import 'package:campus_canteen/screens/orders/orders_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import '../support/fake_realtime.dart';

/// Đơn hàng & realtime qua giao diện: lịch sử offline trước, theo dõi đơn (StreamBuilder), hủy, đặt lại,
/// thông báo + badge, thanh toán tự hoàn tất qua realtime.
void main() {
  late AppHarness app;

  setUp(() async => app = await AppHarness.create());

  /// Màn Theo dõi đơn có chấm "Trực tiếp" nhấp nháy liên tục → không dùng pumpAndSettle (sẽ không bao giờ dừng).
  Future<void> settle(WidgetTester tester, [int frames = 15]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tap(WidgetTester tester, Finder finder, {bool settleAll = false}) async {
    await tester.ensureVisible(finder.first);
    await tester.pump();
    await tester.tap(finder.first);
    if (settleAll) {
      await tester.pumpAndSettle();
    } else {
      await settle(tester);
    }
  }

  Future<void> pumpApp(WidgetTester tester, {Size size = const Size(420, 1600)}) =>
      app.pump(tester, signedIn: AppHarness.student, size: size);

  Future<void> openOrdersTab(WidgetTester tester) async {
    await tap(tester, find.text('Đơn hàng'));
    expect(find.byType(OrdersScreen), findsOneWidget);
  }

  group('Lịch sử đơn', () {
    testWidgets('đồng bộ từ máy chủ → 3 tab theo trạng thái; dữ liệu được lưu SQLite', (tester) async {
      app.backend.seedOrder(status: 'cooking');
      app.backend.seedOrder(status: 'completed', createdAt: '2026-11-15T03:00:00Z');
      app.backend.seedOrder(status: 'cancelled', createdAt: '2026-11-14T03:00:00Z');
      await pumpApp(tester);
      await openOrdersTab(tester);

      expect(find.text('#A001'), findsOneWidget);
      expect(find.text('Đang nấu'), findsOneWidget);
      expect(app.orderDao.rows.keys, contains('order-1'));

      await tap(tester, find.widgetWithText(Tab, 'Hoàn thành'));
      expect(find.text('#A002'), findsOneWidget);
      await tap(tester, find.widgetWithText(Tab, 'Đã hủy'));
      expect(find.text('#A003'), findsOneWidget);
    });

    testWidgets('mất mạng → banner offline, vẫn xem được hóa đơn đã lưu trên máy', (tester) async {
      final order = app.backend.seedOrder(status: 'received');
      await app.orderDao.upsertDetail(_detail(order), 'uid-sv01');
      await pumpApp(tester);
      app.backend.offline = true; // mất mạng SAU khi đã vào app
      await openOrdersTab(tester);
      // Kéo để làm mới → đồng bộ thất bại → banner offline (dữ liệu trên máy vẫn còn).
      await tester.fling(find.text('#A001'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();

      expect(find.text('Không có mạng — đang xem hóa đơn đã lưu trên máy'), findsOneWidget);
      expect(find.text('#A001'), findsOneWidget);

      await tap(tester, find.text('#A001'));
      expect(find.byType(OrderScreen), findsOneWidget);
      expect(find.text('Đang xem hóa đơn lưu trên máy (không có mạng).'), findsOneWidget);
      expect(find.text('Cơm gà xối mỡ'), findsOneWidget, reason: 'món đọc từ SQLite');
    });

    testWidgets('chưa có đơn → trạng thái trống có nút Đặt món', (tester) async {
      await pumpApp(tester);
      await openOrdersTab(tester);
      expect(find.text('Không có đơn đang xử lý'), findsOneWidget);
      expect(find.text('Đặt món ngay'), findsOneWidget);
    });
  });

  group('Theo dõi đơn (realtime)', () {
    testWidgets('StreamBuilder: căn-tin đổi trạng thái → màn hình đổi ngay, dòng thời gian có giờ, SQLite cập nhật', (
      tester,
    ) async {
      app.backend.seedOrder(status: 'received');
      await pumpApp(tester);
      await openOrdersTab(tester);
      await tap(tester, find.text('#A001'));
      expect(find.byType(OrderScreen), findsOneWidget);
      expect(find.text('Hủy đơn'), findsOneWidget, reason: 'còn "Đã nhận" → được hủy');

      app.backend.setStatus('order-1', 'cooking', at: '2026-11-16T03:12:00Z');
      app.realtime.pushOrder(liveOrder('order-1', status: 'cooking'));
      await settle(tester);

      expect(find.text('Đang nấu'), findsWidgets);
      expect(find.text('Trực tiếp'), findsOneWidget);
      expect(find.text('10:12'), findsOneWidget, reason: 'giờ bắt đầu nấu (giờ VN) trên dòng thời gian');
      expect(find.text('Hủy đơn'), findsNothing, reason: 'đã nấu → không cho hủy');
      expect(app.orderDao.rows['order-1']!.status, OrderStatus.cooking);

      app.backend.setStatus('order-1', 'ready', at: '2026-11-16T03:20:00Z');
      app.realtime.pushOrder(liveOrder('order-1', status: 'ready'));
      await settle(tester);
      expect(find.text('Mời nhận món'), findsWidgets);
      expect(find.text('Món đã xong — mời bạn đến quầy'), findsOneWidget);
    });

    testWidgets('hủy đơn: lý do quá ngắn bị chặn; chọn lý do có sẵn → đơn bị hủy', (tester) async {
      app.backend.seedOrder(status: 'received');
      await pumpApp(tester);
      await openOrdersTab(tester);
      await tap(tester, find.text('#A001'));
      await tap(tester, find.text('Hủy đơn'));

      await tester.enterText(find.byType(TextFormField), 'abc');
      await tap(tester, find.text('Xác nhận hủy đơn'));
      expect(find.text('Lý do hủy cần ít nhất 5 ký tự.'), findsOneWidget);

      await tap(tester, find.text('Đặt nhầm món'));
      await tap(tester, find.text('Xác nhận hủy đơn'));
      expect(app.backend.orders['order-1']!['status'], 'cancelled');
      expect(app.backend.orders['order-1']!['cancelReason'], 'Đặt nhầm món');
      expect(find.text('Đơn đã bị hủy'), findsOneWidget);
      expect(app.orderDao.rows['order-1']!.status, OrderStatus.cancelled);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('đơn đã xong → "Đặt lại" thêm đúng món vào giỏ và mở tab Giỏ hàng', (tester) async {
      app.backend.seedOrder(status: 'completed', quantity: 2);
      await pumpApp(tester);
      await openOrdersTab(tester);
      await tap(tester, find.widgetWithText(Tab, 'Hoàn thành'));
      await tap(tester, find.text('#A001'));
      await tap(tester, find.text('Đặt lại'), settleAll: true);

      final row = app.cartDao.rows.single;
      expect((row.foodName, row.quantity), ('Cơm gà xối mỡ', 2));
      expect(find.text('Giỏ hàng (2)'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('xoay ngang → trạng thái/mã bên trái, chi tiết bên phải, không tràn', (tester) async {
      app.backend.seedOrder(status: 'received');
      await pumpApp(tester, size: const Size(900, 420));
      await tap(tester, find.text('Đơn hàng'));
      await tap(tester, find.text('#A001'));
      expect(find.byType(OrderScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      final code = tester.getRect(find.text('Mã nhận món — đưa cho quầy'));
      final items = tester.getRect(find.text('Món đã đặt'));
      expect(items.left, greaterThan(code.right), reason: 'chi tiết nằm bên phải');
    });
  });

  group('Thông báo', () {
    testWidgets('badge số chưa đọc; chạm → đánh dấu đã đọc + mở đúng đơn; Đọc tất cả', (tester) async {
      app.backend.seedOrder(status: 'ready');
      app.realtime.notifications = [
        notification(2, orderId: 'order-1'),
        notification(1, title: 'Giảm 10% hôm nay'),
      ];
      await pumpApp(tester);
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('2')), findsOneWidget);

      await tap(tester, find.text('Thông báo'));
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(find.text('Thông báo (2)'), findsOneWidget);

      await tap(tester, find.text('Món đã sẵn sàng'));
      expect(app.backend.readNotificationIds, {2});
      expect(find.byType(OrderScreen), findsOneWidget);

      Navigator.of(tester.element(find.byType(OrderScreen))).pop();
      await settle(tester);
      expect(find.text('Thông báo (1)'), findsOneWidget);
      await tap(tester, find.text('Đọc tất cả'));
      expect(app.backend.readAllCalls, 1);
      expect(find.text('Thông báo'), findsWidgets);

      // Thông báo mới đến qua Firebase → hiện ngay, không cần làm mới.
      app.realtime.pushNotifications([notification(3, title: 'Đơn đã hoàn thành'), ...app.realtime.notifications]);
      await settle(tester);
      expect(find.text('Đơn đã hoàn thành'), findsOneWidget);
    });

    testWidgets('chưa có thông báo → trạng thái trống', (tester) async {
      await pumpApp(tester);
      await tap(tester, find.text('Thông báo'));
      expect(find.text('Chưa có thông báo'), findsOneWidget);
    });
  });

  testWidgets('thanh toán QR: Firebase báo đã nhận tiền → tự chuyển sang màn thành công (không cần bấm)', (tester) async {
    await app.cartDao.add(
      CartItem(
        userId: 'uid-sv01',
        foodId: 1,
        foodName: 'Cơm gà xối mỡ',
        unitPrice: 35000,
        quantity: 1,
        createdAt: DateTime.utc(2026),
      ),
    );
    await pumpApp(tester);
    await tap(tester, find.text('Giỏ hàng'), settleAll: true);
    await tap(tester, find.text('Thanh toán'), settleAll: true);
    await tap(tester, find.text('Chuyển khoản (QR)'), settleAll: true);
    await tap(tester, find.text('Đặt món · 35.000đ'));
    expect(find.byType(PaymentScreen), findsOneWidget);

    app.backend.paidOrderIds.add('order-1');
    app.realtime.pushOrder(liveOrder('order-1', paymentMethod: 'bankTransfer', paymentStatus: 'paid'));
    await settle(tester, 20);
    expect(find.byType(OrderPlacedScreen), findsOneWidget);
    expect(find.text('Đã thanh toán'), findsOneWidget);

    await tap(tester, find.text('Theo dõi đơn'));
    expect(find.byType(OrderScreen), findsOneWidget);
  });
}

/// Chi tiết đơn (để lưu sẵn vào SQLite giả) — đi qua JSON giống dữ liệu backend trả về.
OrderDetail _detail(Map<String, Object?> json) =>
    OrderDetail.fromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
