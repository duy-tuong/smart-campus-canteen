import 'package:campus_canteen/data/device/image_source_service.dart';
import 'package:campus_canteen/providers/auth_provider.dart';
import 'package:campus_canteen/screens/profile/account_screen.dart';
import 'package:campus_canteen/screens/profile/edit_profile_screen.dart';
import 'package:campus_canteen/screens/reviews/my_reviews_screen.dart';
import 'package:campus_canteen/screens/reviews/review_order_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/app_harness.dart';
import '../support/fake_realtime.dart';

/// Tài khoản & đánh giá qua giao diện: sửa hồ sơ, ảnh đại diện, đánh giá đơn, đánh giá của tôi.
void main() {
  late AppHarness app;

  setUp(() async => app = await AppHarness.create());

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder.first);
    await tester.pump();
    await tester.tap(finder.first);
    await tester.pumpAndSettle();
  }

  Future<void> pumpApp(WidgetTester tester) => app.pump(tester, signedIn: AppHarness.student);

  Future<void> openAccount(WidgetTester tester) async {
    await tap(tester, find.text('Tài khoản'));
    expect(find.byType(AccountScreen), findsOneWidget);
  }

  AuthProvider auth(WidgetTester tester) =>
      Provider.of<AuthProvider>(tester.element(find.byType(AccountScreen, skipOffstage: false)), listen: false);

  /// Cho SnackBar hết hạn trước khi kết thúc test.
  Future<void> settleSnackBars(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  group('Hồ sơ', () {
    testWidgets('sửa họ tên + số điện thoại; MSSV đã có thì khóa; số điện thoại sai bị chặn', (tester) async {
      await pumpApp(tester);
      await openAccount(tester);
      await tap(tester, find.text('Nguyễn Văn An'));
      expect(find.byType(EditProfileScreen), findsOneWidget);

      final code = tester.widget<TextField>(
        find.descendant(of: find.widgetWithText(TextFormField, 'Mã số sinh viên'), matching: find.byType(TextField)),
      );
      expect(code.readOnly, isTrue);
      expect(find.text('MSSV đã xác nhận — liên hệ căn-tin nếu cần đổi.'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Họ và tên'), 'Nguyễn Văn Bình');
      await tester.enterText(find.widgetWithText(TextFormField, 'Số điện thoại (không bắt buộc)'), '123');
      await tap(tester, find.text('Lưu thay đổi'));
      expect(find.text('Số điện thoại dạng 0xxxxxxxxx hoặc +84xxxxxxxxx.'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Số điện thoại (không bắt buộc)'), '0912345678');
      await tap(tester, find.text('Lưu thay đổi'));
      expect(find.byType(EditProfileScreen), findsNothing, reason: 'lưu xong quay lại');
      expect(find.text('Nguyễn Văn Bình'), findsOneWidget, reason: 'thẻ hồ sơ cập nhật ngay');
      expect(app.backend.profiles['uid-sv01']!['phone'], '0912345678');
      await settleSnackBars(tester);
    });

    testWidgets('đổi ảnh đại diện từ thư viện (upload multipart) rồi gỡ ảnh', (tester) async {
      await pumpApp(tester);
      await openAccount(tester);
      await tap(tester, find.text('Nguyễn Văn An'));

      await tap(tester, find.byTooltip('Đổi ảnh đại diện'));
      await tap(tester, find.text('Chọn từ thư viện'));
      expect(app.images.requests, [PickSource.gallery]);
      expect(auth(tester).profile!.avatarUrl, 'http://api.test/uploads/avatars/uid-sv01.png');
      expect(find.text('Đã cập nhật ảnh đại diện.'), findsOneWidget);

      await tap(tester, find.byTooltip('Đổi ảnh đại diện'));
      await tap(tester, find.text('Gỡ ảnh đại diện'));
      expect(auth(tester).profile!.avatarUrl, isNull);
      await settleSnackBars(tester);
    });

    testWidgets('hủy chọn ảnh → không gọi máy chủ', (tester) async {
      app.images.cancel = true;
      await pumpApp(tester);
      await openAccount(tester);
      await tap(tester, find.text('Nguyễn Văn An'));
      await tap(tester, find.byTooltip('Đổi ảnh đại diện'));
      await tap(tester, find.text('Chụp ảnh'));
      expect(app.images.requests, [PickSource.camera]);
      expect(app.backend.calls.where((c) => c.contains('avatar')), isEmpty);
    });
  });

  group('Đánh giá đơn hàng', () {
    Future<void> openReviewOrder(WidgetTester tester) async {
      await tap(tester, find.text('Đơn hàng'));
      await tap(tester, find.widgetWithText(Tab, 'Hoàn thành'));
      await tap(tester, find.text('#A001'));
      await tap(tester, find.text('Đánh giá món'));
      expect(find.byType(ReviewOrderScreen), findsOneWidget);
    }

    testWidgets('chấm sao + nhận xét → gửi; sửa số sao → lưu; xóa', (tester) async {
      app.backend.seedOrder(status: 'completed', foodId: 4);
      await pumpApp(tester);
      await openReviewOrder(tester);

      expect(find.text('Món số 4'), findsOneWidget);
      final send = find.widgetWithText(FilledButton, 'Gửi đánh giá');
      expect(tester.widget<FilledButton>(send).onPressed, isNull, reason: 'chưa chọn sao');

      await tap(tester, find.byTooltip('5 sao'));
      expect(find.text('Tuyệt vời'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Rất ngon, nóng hổi');
      await tap(tester, find.text('Gửi đánh giá'));
      final saved = app.backend.reviews.values.single;
      expect((saved['rating'], saved['comment'], saved['foodId']), (5, 'Rất ngon, nóng hổi', 4));
      expect(find.textContaining('Cảm ơn bạn!'), findsOneWidget);
      expect(find.textContaining('đã đánh giá 1/1 món'), findsOneWidget, reason: 'bộ đếm cập nhật ngay');

      final save = find.widgetWithText(FilledButton, 'Lưu thay đổi');
      expect(tester.widget<FilledButton>(save).onPressed, isNull, reason: 'chưa thay đổi gì');
      await tap(tester, find.byTooltip('3 sao'));
      await tap(tester, find.text('Lưu thay đổi'));
      expect(app.backend.reviews.values.single['rating'], 3);

      await tap(tester, find.text('Xóa'));
      await tap(tester, find.widgetWithText(FilledButton, 'Xóa'));
      expect(app.backend.reviews, isEmpty);
      expect(find.text('Gửi đánh giá'), findsOneWidget);
      expect(find.textContaining('đã đánh giá 0/1 món'), findsOneWidget);
      await settleSnackBars(tester);
    });

    testWidgets('quá hạn đánh giá → chỉ xem, không chấm được', (tester) async {
      app.backend.seedOrder(status: 'completed', foodId: 4);
      app.backend.reviewWindowOpen = false;
      await pumpApp(tester);
      await openReviewOrder(tester);
      expect(find.text('Đơn này không còn trong hạn đánh giá.'), findsOneWidget);
      expect(find.text('Gửi đánh giá'), findsNothing);
      final star = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.star_outline_rounded).first);
      expect(star.onPressed, isNull);
    });

    testWidgets('đơn chưa hoàn thành → không có nút Đánh giá', (tester) async {
      app.backend.seedOrder(status: 'received');
      await pumpApp(tester);
      await tap(tester, find.text('Đơn hàng'));
      await tester.tap(find.text('#A001'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Đánh giá món'), findsNothing);
    });
  });

  group('Đánh giá của tôi', () {
    testWidgets('hiện lý do bị ẩn + phản hồi của căn-tin; sửa trong hạn; xóa', (tester) async {
      final order = app.backend.seedOrder(status: 'completed');
      app.backend.addReview(
        orderId: order['id']! as String,
        foodId: 1,
        foodName: 'Cơm gà xối mỡ',
        rating: 1,
        comment: 'Nội dung không phù hợp',
        hidden: true,
        hiddenReason: 'Ngôn từ không phù hợp',
      );
      app.backend.addReview(
        orderId: order['id']! as String,
        foodId: 2,
        foodName: 'Trà sữa trân châu',
        rating: 4,
        comment: 'Ngon',
        staffReply: 'Cảm ơn bạn đã ủng hộ!',
      );
      await pumpApp(tester);
      await openAccount(tester);
      await tap(tester, find.text('Đánh giá của tôi'));
      expect(find.byType(MyReviewsScreen), findsOneWidget);
      expect(find.text('Đã bị ẩn khỏi trang món: Ngôn từ không phù hợp'), findsOneWidget);
      expect(find.text('Căn-tin: Cảm ơn bạn đã ủng hộ!'), findsOneWidget);

      // Trà sữa (mới nhất, ở đầu danh sách) — sửa thành 5 sao.
      await tap(tester, find.byTooltip('Tùy chọn').first);
      await tap(tester, find.text('Sửa đánh giá'));
      await tap(tester, find.byTooltip('5 sao'));
      await tap(tester, find.widgetWithText(FilledButton, 'Lưu'));
      expect(app.backend.reviews.values.firstWhere((r) => r['foodId'] == 2)['rating'], 5);

      // Đánh giá bị ẩn: chỉ có Xóa (không có Sửa).
      await tap(tester, find.byTooltip('Tùy chọn').last);
      expect(find.text('Sửa đánh giá'), findsNothing);
      await tap(tester, find.text('Xóa'));
      await tap(tester, find.widgetWithText(FilledButton, 'Xóa'));
      expect(app.backend.reviews, hasLength(1));
      expect(find.text('Cơm gà xối mỡ'), findsNothing);
      await settleSnackBars(tester);
    });

    testWidgets('thông báo "căn-tin trả lời đánh giá" → mở Đánh giá của tôi', (tester) async {
      app.realtime.notifications = [notification(1, title: 'Căn-tin đã trả lời đánh giá của bạn', type: 'review')];
      await pumpApp(tester);
      await tap(tester, find.text('Thông báo'));
      await tap(tester, find.text('Căn-tin đã trả lời đánh giá của bạn'));
      expect(find.byType(MyReviewsScreen), findsOneWidget);
    });
  });
}
