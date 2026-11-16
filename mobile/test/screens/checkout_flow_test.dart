import 'package:campus_canteen/models/cart_item.dart';
import 'package:campus_canteen/screens/cart/cart_screen.dart';
import 'package:campus_canteen/screens/checkout/checkout_screen.dart';
import 'package:campus_canteen/screens/checkout/order_placed_screen.dart';
import 'package:campus_canteen/screens/checkout/payment_screen.dart';
import 'package:campus_canteen/screens/checkout/voucher_picker_screen.dart';
import 'package:campus_canteen/screens/menu/menu_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../support/app_harness.dart';

/// Giỏ hàng → Thanh toán → Đặt món (tiền mặt / chuyển khoản) qua giao diện.
void main() {
  late AppHarness app;

  setUp(() async => app = await AppHarness.create());

  CartItem line(int foodId, String name, int price, {int quantity = 1, List<CartItemOption> options = const []}) =>
      CartItem(
        userId: 'uid-sv01',
        foodId: foodId,
        foodName: name,
        unitPrice: price,
        quantity: quantity,
        createdAt: DateTime.utc(2026, 11, 16, 3, foodId),
        options: options,
      );

  Future<void> pumpWithCart(WidgetTester tester, List<CartItem> items, {Size size = const Size(420, 1600)}) async {
    for (final item in items) {
      await app.cartDao.add(item);
    }
    await app.pump(tester, signedIn: AppHarness.student, size: size);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder.first);
    await tester.pump();
    await tester.tap(finder.first);
    await tester.pumpAndSettle();
  }

  Future<void> openCart(WidgetTester tester) => tap(tester, find.text('Giỏ hàng'));

  Future<void> openCheckout(WidgetTester tester) async {
    await openCart(tester);
    await tap(tester, find.text('Thanh toán'));
    expect(find.byType(CheckoutScreen), findsOneWidget);
  }

  /// Cho SnackBar hết hạn trước khi kết thúc test.
  Future<void> settleSnackBars(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  const sizeL = CartItemOption(optionId: 21, groupName: 'Size', optionName: 'L', extraPrice: 6000);

  group('Giỏ hàng', () {
    testWidgets('giỏ trống → trạng thái trống, nút "Xem thực đơn" về tab Thực đơn', (tester) async {
      await pumpWithCart(tester, const []);
      await openCart(tester);
      expect(find.text('Giỏ hàng đang trống'), findsOneWidget);
      await tap(tester, find.text('Xem thực đơn'));
      expect(find.byType(MenuScreen), findsOneWidget);
    });

    testWidgets('hiển thị món + tùy chọn, tạm tính; tăng số lượng; vuốt xóa rồi Hoàn tác', (tester) async {
      await pumpWithCart(tester, [line(2, 'Trà sữa trân châu', 25000, options: const [sizeL]), line(4, 'Món số 4', 20400)]);
      await openCart(tester);
      expect(find.byType(CartScreen), findsOneWidget);
      expect(find.text('Giỏ hàng (2)'), findsOneWidget);
      expect(find.text('L'), findsOneWidget);
      expect(find.text('51.400đ'), findsOneWidget, reason: '31.000 + 20.400');

      await tap(tester, find.byTooltip('Tăng').first);
      expect(find.text('Giỏ hàng (3)'), findsOneWidget);
      expect(find.text('62.000đ'), findsOneWidget, reason: 'dòng trà sữa ×2');

      await tester.drag(find.text('Món số 4'), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('Món số 4'), findsNothing);
      expect(find.text('Đã xóa Món số 4'), findsOneWidget);

      await tap(tester, find.text('Hoàn tác'));
      expect(find.text('Món số 4'), findsOneWidget);
      await settleSnackBars(tester);
    });

    testWidgets('màn rộng: danh sách bên trái, tổng tiền bên phải', (tester) async {
      await pumpWithCart(tester, [line(4, 'Món số 4', 20400)], size: const Size(1300, 900));
      await openCart(tester);
      final list = tester.getRect(find.text('Món số 4'));
      final pay = tester.getRect(find.text('Thanh toán'));
      expect(pay.left, greaterThan(list.right), reason: 'khung tổng tiền nằm bên phải');
    });
  });

  group('Thanh toán & đặt món', () {
    testWidgets('tiền mặt: báo giá từ máy chủ → Đặt món → màn thành công có mã nhận món; giỏ trống, hóa đơn lưu máy', (
      tester,
    ) async {
      await pumpWithCart(tester, [line(2, 'Trà sữa trân châu', 25000, quantity: 2, options: const [sizeL])]);
      await openCheckout(tester);

      expect(find.text('2 × Trà sữa trân châu'), findsOneWidget);
      expect(find.text('Đặt món · 62.000đ'), findsOneWidget);
      expect(find.text('Sớm nhất'), findsOneWidget);

      await tap(tester, find.text('Đặt món · 62.000đ'));
      expect(find.byType(OrderPlacedScreen), findsOneWidget);
      expect(find.text('Đặt món thành công!'), findsOneWidget);
      expect(find.text('A001'), findsOneWidget);

      expect(app.backend.createdBodies.single['paymentMethod'], 'cash');
      expect(app.backend.createdBodies.single['items'], [
        {
          'foodId': 2,
          'quantity': 2,
          'optionIds': [21],
          'note': null,
        },
      ]);
      expect(app.cartDao.rows, isEmpty);
      expect(app.orderDao.rows.keys, ['order-1']);

      await tap(tester, find.text('Tiếp tục xem thực đơn'));
      expect(find.byType(MenuScreen), findsOneWidget);
    });

    testWidgets('món hết suất → dòng tô đỏ, nút Đặt bị khóa; "Bỏ món" → đặt được', (tester) async {
      await pumpWithCart(tester, [line(3, 'Bánh flan', 12000), line(4, 'Món số 4', 20400)]);
      await openCheckout(tester);

      expect(find.text('Bánh flan đã hết suất hôm nay.'), findsOneWidget);
      expect(find.text('Sửa các món tô đỏ để đặt'), findsOneWidget);
      final place = find.widgetWithText(FilledButton, 'Đặt món · 32.400đ');
      expect(tester.widget<FilledButton>(place).onPressed, isNull);

      await tap(tester, find.text('Bỏ món'));
      expect(find.text('Bánh flan đã hết suất hôm nay.'), findsNothing);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Đặt món · 20.400đ')).onPressed, isNotNull);
    });

    testWidgets('số lượng vượt suất còn lại → "Giảm còn N"', (tester) async {
      await pumpWithCart(tester, [line(1, 'Cơm gà xối mỡ', 35000, quantity: 10)]);
      await openCheckout(tester);
      expect(find.text('Chỉ còn 8 suất.'), findsOneWidget);
      await tap(tester, find.text('Giảm còn 8'));
      expect(find.text('8 × Cơm gà xối mỡ'), findsOneWidget);
      expect(find.text('Đặt món · 280.000đ'), findsOneWidget);
    });

    testWidgets('chọn voucher (Navigator.push trả kết quả) → báo giá lại có giảm giá', (tester) async {
      await pumpWithCart(tester, [line(1, 'Cơm gà xối mỡ', 35000)]);
      await openCheckout(tester);
      await tap(tester, find.text('Chọn hoặc nhập mã'));
      expect(find.byType(VoucherPickerScreen), findsOneWidget);
      expect(find.text('Mua thêm 165.000đ để dùng mã'), findsOneWidget, reason: 'BIGSALE cần đơn 200k');
      expect(find.text('Dự kiến giảm 3.500đ'), findsOneWidget);

      await tap(tester, find.widgetWithText(TextButton, 'Dùng').first);
      expect(find.byType(CheckoutScreen), findsOneWidget);
      expect(find.text('GIAM10'), findsOneWidget);
      expect(find.text('Giảm 3.500đ'), findsOneWidget);
      expect(find.text('Đặt món · 31.500đ'), findsOneWidget);

      await tap(tester, find.byTooltip('Bỏ mã'));
      expect(find.text('Đặt món · 35.000đ'), findsOneWidget);
    });

    testWidgets('mã nhập tay không hợp lệ → báo lỗi nhưng vẫn đặt được (không giảm)', (tester) async {
      await pumpWithCart(tester, [line(1, 'Cơm gà xối mỡ', 35000)]);
      await openCheckout(tester);
      await tap(tester, find.text('Chọn hoặc nhập mã'));
      await tester.enterText(find.byType(TextField), 'sai123');
      await tap(tester, find.text('Áp dụng'));
      expect(find.text('SAI123'), findsOneWidget);
      expect(find.text('Mã giảm giá không tồn tại.'), findsOneWidget);
      expect(find.text('Đặt món · 35.000đ'), findsOneWidget);
    });

    testWidgets('mất mạng ngay sau khi máy chủ tạo đơn → bấm lại dùng CÙNG key → không tạo đơn trùng', (tester) async {
      await pumpWithCart(tester, [line(4, 'Món số 4', 20400)]);
      await openCheckout(tester);
      app.backend.dropNextCreateResponse = true;

      await tap(tester, find.text('Đặt món · 20.400đ'));
      expect(find.byType(CheckoutScreen), findsOneWidget, reason: 'app chưa biết đơn đã được tạo');
      expect(find.textContaining('không bị tạo trùng'), findsOneWidget);

      await tap(tester, find.text('Đặt món · 20.400đ'));
      expect(find.byType(OrderPlacedScreen), findsOneWidget);
      expect(app.backend.orders, hasLength(1), reason: 'chỉ MỘT đơn');
      expect(app.backend.idempotencyKeys, hasLength(2));
      expect(app.backend.idempotencyKeys.toSet(), hasLength(1), reason: 'hai lần gửi cùng một key');
      await settleSnackBars(tester);
    });

    testWidgets('căn-tin đóng cửa → banner + nút Đặt món bị khóa', (tester) async {
      app.backend.canteenOpen = false;
      await pumpWithCart(tester, [line(4, 'Món số 4', 20400)]);
      await openCheckout(tester);
      expect(find.textContaining('Căn-tin đang đóng cửa'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Đặt món · 20.400đ')).onPressed, isNull);
    });

    testWidgets('chuyển khoản: QR + thông tin chuyển tay; đã trả tiền → "Tôi đã chuyển khoản" → thành công', (
      tester,
    ) async {
      await pumpWithCart(tester, [line(1, 'Cơm gà xối mỡ', 35000)]);
      await openCheckout(tester);
      await tap(tester, find.text('Chuyển khoản (QR)'));
      await tap(tester, find.text('Đặt món · 35.000đ'));

      expect(find.byType(PaymentScreen), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('SC0000001'), findsOneWidget);
      expect(find.text('0123456789'), findsOneWidget);
      expect(find.textContaining('để thanh toán'), findsOneWidget, reason: 'đếm ngược');

      await tap(tester, find.text('Tôi đã chuyển khoản'));
      expect(find.byType(PaymentScreen), findsOneWidget, reason: 'chưa có tiền → ở lại');
      expect(find.textContaining('Chưa nhận được tiền'), findsOneWidget);

      app.backend.paidOrderIds.add('order-1');
      await tap(tester, find.text('Tôi đã chuyển khoản'));
      expect(find.byType(OrderPlacedScreen), findsOneWidget);
      expect(find.text('Đã thanh toán'), findsOneWidget);
      expect(app.orderDao.rows['order-1']!.paymentStatus.name, 'paid', reason: 'cập nhật hóa đơn trên máy');
      await settleSnackBars(tester);
    });
  });
}
