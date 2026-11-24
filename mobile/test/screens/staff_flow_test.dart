import 'package:campus_canteen/data/firebase/auth_service.dart';
import 'package:campus_canteen/screens/staff/food_form_screen.dart';
import 'package:campus_canteen/screens/staff/order_board_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import '../support/fake_realtime.dart';

/// Nhân viên căn-tin qua giao diện: bảng đơn realtime, quản lý món / danh mục / voucher / đánh giá.
void main() {
  late AppHarness app;

  setUp(() async => app = await AppHarness.create());

  const staff = AuthUser(uid: 'uid-staff', email: 'staff@smartcanteen.vn');

  Future<void> pumpStaff(WidgetTester tester, {Size size = const Size(420, 1600)}) =>
      app.pump(tester, signedIn: staff, size: size);

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder.first);
    await tester.pump();
    await tester.tap(finder.first);
    await tester.pumpAndSettle();
  }

  Future<void> settleSnackBars(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  /// Đơn có trên backend giả + Firebase giả (như backend vừa ghi lên Firebase).
  void seedLive(String status, {String paymentMethod = 'cash', String paymentStatus = 'pending'}) {
    final order = app.backend.seedOrder(status: status, paymentMethod: paymentMethod)
      ..['paymentStatus'] = paymentStatus;
    app.realtime.pushOrder(
      liveOrder(
        order['id']! as String,
        status: status,
        pickupCode: order['pickupCode']! as String,
        paymentMethod: paymentMethod,
        paymentStatus: paymentStatus,
      ),
    );
  }

  group('Bảng đơn (realtime)', () {
    testWidgets('điện thoại: 3 tab có đếm; bấm "Bắt đầu nấu" → gọi API; Firebase cập nhật → thẻ chuyển tab', (
      tester,
    ) async {
      seedLive('received');
      await pumpStaff(tester);
      expect(find.byType(OrderBoardScreen), findsOneWidget);
      expect(find.text('Đã nhận (1)'), findsOneWidget);
      expect(find.text('#A001'), findsOneWidget);
      expect(find.text('Thu 35.000đ'), findsOneWidget);
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('1')), findsOneWidget);

      await tap(tester, find.text('Bắt đầu nấu'));
      expect(app.backend.statusChanges, [('order-1', 'cooking')]);

      app.realtime.pushOrder(liveOrder('order-1', status: 'cooking'));
      await tester.pumpAndSettle();
      expect(find.text('Đã nhận (0)'), findsOneWidget);
      expect(find.text('Đang nấu (1)'), findsOneWidget);
      await tap(tester, find.text('Đang nấu (1)'));
      expect(find.text('Xong — mời nhận'), findsOneWidget);
      await settleSnackBars(tester);
    });

    testWidgets('đơn chuyển khoản chưa trả → không cho nấu; xác nhận đã nhận tiền', (tester) async {
      seedLive('received', paymentMethod: 'bankTransfer');
      await pumpStaff(tester);
      expect(find.text('Bắt đầu nấu'), findsNothing);
      expect(find.text('Chờ CK'), findsOneWidget);
      expect(find.textContaining('chưa được nấu'), findsOneWidget);

      await tap(tester, find.text('Xác nhận đã nhận tiền'));
      await tap(tester, find.text('Đã nhận tiền'));
      expect(app.backend.orders['order-1']!['paymentStatus'], 'paid');
      await settleSnackBars(tester);
    });

    testWidgets('hai nhân viên bấm cùng lúc (409) → báo đơn vừa được cập nhật ở máy khác', (tester) async {
      seedLive('received');
      app.backend.statusConflict = true;
      await pumpStaff(tester);
      await tap(tester, find.text('Bắt đầu nấu'));
      expect(find.textContaining('vừa được cập nhật ở máy khác'), findsOneWidget);
      await settleSnackBars(tester);
    });

    testWidgets('màn rộng: 3 cột kanban, không có tab; tìm theo mã nhận món', (tester) async {
      seedLive('received');
      seedLive('cooking');
      await pumpStaff(tester, size: const Size(1300, 900));
      expect(find.byType(TabBar), findsNothing);
      expect(find.text('Đã nhận (1)'), findsOneWidget);
      expect(find.text('Đang nấu (1)'), findsOneWidget);
      expect(find.text('Mời nhận món (0)'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '#A002');
      await tester.pumpAndSettle();
      // Chỉ đếm trong thẻ đơn (ô tìm kiếm cũng đang chứa chữ "#A002").
      expect(find.descendant(of: find.byType(Card), matching: find.text('#A001')), findsNothing);
      expect(find.descendant(of: find.byType(Card), matching: find.text('#A002')), findsOneWidget);
    });
  });

  group('Quản lý thực đơn', () {
    Future<void> openMenu(WidgetTester tester) async {
      await pumpStaff(tester);
      await tap(tester, find.text('Quản lý'));
      await tap(tester, find.text('Thực đơn'));
    }

    testWidgets('công tắc Còn bán → PATCH availability', (tester) async {
      await openMenu(tester);
      expect(find.text('Cơm gà xối mỡ'), findsOneWidget);
      final toggle = find.descendant(
        of: find.ancestor(of: find.text('Cơm gà xối mỡ'), matching: find.byType(ListTile)),
        matching: find.byType(Switch),
      );
      await tap(tester, toggle);
      expect(app.backend.foods.firstWhere((f) => f['id'] == 1)['isAvailable'], isFalse);
      expect(find.text('Cơm gà xối mỡ: tạm ngưng bán'), findsOneWidget);
      await settleSnackBars(tester);
    });

    testWidgets('thêm món: kiểm tra giá + nhóm tùy chọn; lưu gửi đủ nhóm tùy chọn', (tester) async {
      await openMenu(tester);
      await tap(tester, find.text('Thêm món'));
      expect(find.byType(FoodFormScreen), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Tên món'), 'Bánh bao');
      await tester.enterText(find.widgetWithText(TextFormField, 'Mô tả'), 'Bánh bao nhân thịt trứng cút');
      await tester.enterText(find.widgetWithText(TextFormField, 'Giá (đ)'), '500');
      await tap(tester, find.text('Thêm nhóm'));
      await tap(tester, find.text('Thêm vào thực đơn'));
      expect(find.text('Từ 1.000đ đến 1.000.000đ.'), findsOneWidget);
      expect(find.text('Nhập tên nhóm'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Giá (đ)'), '15000');
      await tester.enterText(find.widgetWithText(TextFormField, 'Tên nhóm (VD: Size)'), 'Nhân');
      await tester.enterText(find.widgetWithText(TextFormField, 'Tùy chọn 1'), 'Thêm trứng');
      await tester.enterText(find.widgetWithText(TextFormField, '+ giá (đ)'), '3000');
      await tap(tester, find.text('Thêm vào thực đơn'));

      expect(find.byType(FoodFormScreen), findsNothing, reason: 'lưu xong quay lại');
      final created = app.backend.foods.last;
      expect((created['name'], created['price']), ('Bánh bao', 15000));
      final group = app.backend.savedGroups[created['id']]!.single;
      expect(group['name'], 'Nhân');
      expect((group['options']! as List).single, containsPair('extraPrice', 3000));
      await settleSnackBars(tester);
    });

    testWidgets('sửa món mà người khác vừa sửa (409) → hỏi tải lại', (tester) async {
      await openMenu(tester);
      await tap(tester, find.text('Cơm gà xối mỡ'));
      app.backend.foodVersions[1] = 'BBBB'; // người khác vừa lưu
      await tester.enterText(find.widgetWithText(TextFormField, 'Giá (đ)'), '36000');
      await tap(tester, find.text('Lưu thay đổi'));
      expect(find.text('Món vừa được sửa ở máy khác'), findsOneWidget);
      await tap(tester, find.text('Tải lại'));
      expect(find.widgetWithText(TextFormField, '35000'), findsOneWidget, reason: 'đã tải lại dữ liệu mới nhất');
    });
  });

  testWidgets('danh mục: thêm mới; xóa danh mục còn món bị chặn', (tester) async {
    await pumpStaff(tester);
    await tap(tester, find.text('Quản lý'));
    await tap(tester, find.text('Danh mục'));
    await tap(tester, find.byTooltip('Xóa Cơm'));
    await tap(tester, find.widgetWithText(FilledButton, 'Xóa'));
    expect(find.text('Danh mục còn món — hãy chuyển hoặc xóa món trước.'), findsOneWidget);
    await settleSnackBars(tester);

    await tap(tester, find.text('Thêm danh mục'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Tên danh mục'), 'Tráng miệng');
    await tap(tester, find.byTooltip('icecream'));
    await tap(tester, find.widgetWithText(FilledButton, 'Lưu'));
    expect(find.text('Tráng miệng'), findsOneWidget);
    expect(app.backend.categories.last['icon'], 'icecream');
  });

  testWidgets('voucher: kiểm tra mã và % ≤ 100; tạo thành công hiện trong danh sách', (tester) async {
    await pumpStaff(tester);
    await tap(tester, find.text('Quản lý'));
    await tap(tester, find.text('Voucher'));
    expect(find.text('Chưa có voucher'), findsOneWidget);
    await tap(tester, find.text('Tạo voucher').last);

    await tester.enterText(find.widgetWithText(TextFormField, 'Mã (VD: GIAM10)'), 'ab');
    await tester.enterText(find.widgetWithText(TextFormField, 'Giảm (%)'), '120');
    await tap(tester, find.text('Lưu voucher'));
    expect(find.text('3–30 chữ cái hoặc số.'), findsOneWidget);
    expect(find.text('Từ 1 đến 100.'), findsOneWidget);
    expect(find.text('Mô tả dài từ 5 ký tự.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Mã (VD: GIAM10)'), 'giam20');
    await tester.enterText(find.widgetWithText(TextFormField, 'Mô tả cho sinh viên'), 'Giảm 20% tuần lễ vàng');
    await tester.enterText(find.widgetWithText(TextFormField, 'Giảm (%)'), '20');
    await tap(tester, find.text('Lưu voucher'));
    expect(find.text('GIAM20'), findsOneWidget);
    expect(app.backend.vouchersAdmin.single['discountType'], 'percent');
    await settleSnackBars(tester);
  });

  testWidgets('kiểm duyệt đánh giá: trả lời → rời danh sách "Chưa trả lời"; ẩn kèm lý do', (tester) async {
    final order = app.backend.seedOrder(status: 'completed');
    app.backend.addReview(
      orderId: order['id']! as String,
      foodId: 1,
      foodName: 'Cơm gà xối mỡ',
      rating: 2,
      comment: 'Hơi nguội',
    );
    await pumpStaff(tester);
    await tap(tester, find.text('Quản lý'));
    await tap(tester, find.text('Đánh giá'));
    expect(find.text('Hơi nguội'), findsOneWidget);

    await tap(tester, find.text('Trả lời'));
    await tester.enterText(find.byType(TextField), 'Xin lỗi bạn, lần sau căn-tin sẽ hâm nóng kỹ hơn.');
    await tap(tester, find.text('Lưu'));
    expect(app.backend.reviews.values.single['staffReply'], startsWith('Xin lỗi bạn'));
    expect(find.text('Đã trả lời hết đánh giá'), findsOneWidget);

    await tap(tester, find.text('Tất cả'));
    await tap(tester, find.text('Ẩn'));
    await tester.enterText(find.byType(TextField), 'Spam');
    await tap(tester, find.text('Lưu'));
    expect(app.backend.reviews.values.single['isHidden'], isTrue);
    expect(find.text('Đang ẩn: Spam'), findsOneWidget);
    await settleSnackBars(tester);
  });
}
