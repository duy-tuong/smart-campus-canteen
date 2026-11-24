import 'package:campus_canteen/core/utils/vn_time.dart';
import 'package:campus_canteen/data/firebase/auth_service.dart';
import 'package:campus_canteen/screens/admin/user_detail_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';

/// Thống kê (staff/admin) và quản trị tài khoản (admin) qua giao diện.
void main() {
  late AppHarness app;

  setUp(() async => app = await AppHarness.create());

  const staff = AuthUser(uid: 'uid-staff', email: 'staff@smartcanteen.vn');
  const admin = AuthUser(uid: 'uid-admin', email: 'admin@smartcanteen.vn');

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

  Future<void> openStats(WidgetTester tester, {AuthUser user = staff, Size size = const Size(420, 2600)}) async {
    await app.pump(tester, signedIn: user, size: size);
    await tap(tester, find.text('Thống kê'));
  }

  /// Query của lần gọi gần nhất tới /api/stats/[endpoint].
  Map<String, String> lastQuery(String endpoint) => app.backend.statsRequests.lastWhere((r) => r.$1 == endpoint).$2;

  final segmented = find.byWidgetPredicate((w) => w is SegmentedButton);
  Finder segment(String text) => find.descendant(of: segmented, matching: find.text(text));

  String day(int daysAgo) => VnTime.isoDate(VnTime.today().subtract(Duration(days: daysAgo)));

  group('Thống kê', () {
    testWidgets('mặc định 7 ngày: thẻ tổng quan (FittedBox), so với kỳ trước, biểu đồ, danh mục, top món', (
      tester,
    ) async {
      await openStats(tester);
      expect(lastQuery('overview'), {'from': day(6), 'to': day(0)});
      expect(lastQuery('revenue')['groupBy'], 'day');

      expect(find.text('2.410.000đ'), findsOneWidget);
      expect(find.ancestor(of: find.text('2.410.000đ'), matching: find.byType(FittedBox)), findsOneWidget);
      expect(
        find.textContaining('+20,5%', findRichText: true),
        findsOneWidget,
        reason: 'doanh thu tăng so với kỳ trước',
      );
      expect(
        find.textContaining('−12,5%', findRichText: true),
        findsOneWidget,
        reason: '42 đơn so với 48 đơn kỳ trước',
      );
      expect(find.byType(LineChart), findsOneWidget);
      expect(find.byType(BarChart), findsOneWidget);
      expect(find.text('Đông nhất 11:00–11:59 · 85 đơn'), findsOneWidget);
      expect(find.text('64,3%'), findsOneWidget);
      expect(find.text('Trà sữa trân châu'), findsOneWidget);
      expect(find.text('Cần hoàn tiền (1 đơn)'), findsOneWidget);
    });

    testWidgets('đổi khoảng / cách nhóm / tiêu chí top món → gọi lại đúng tham số', (tester) async {
      await openStats(tester);

      await tap(tester, find.text('30 ngày'));
      expect(lastQuery('overview'), {'from': day(29), 'to': day(0)});

      await tap(tester, segment('Tuần'));
      expect(lastQuery('revenue')['groupBy'], 'week');

      await tap(tester, segment('Doanh thu'));
      expect(lastQuery('top-foods')['sortBy'], 'revenue');
      expect(find.text('9,7tr'), findsOneWidget, reason: 'cột số liệu đổi sang doanh thu');

      final before = app.backend.statsRequests.where((r) => r.$1 == 'revenue').length;
      await tap(tester, find.text('Hôm nay'));
      expect(lastQuery('overview'), {'from': day(0), 'to': day(0)});
      expect(
        app.backend.statsRequests.where((r) => r.$1 == 'revenue').length,
        before,
        reason: '1 ngày: không vẽ đường',
      );
      expect(find.byType(LineChart), findsNothing);
    });

    testWidgets('khoảng không có đơn → trạng thái trống', (tester) async {
      app.backend.statsEmpty = true;
      await openStats(tester);
      expect(find.text('Chưa có đơn trong khoảng này'), findsOneWidget);
      expect(find.byType(LineChart), findsNothing);
    });

    testWidgets('một khối lỗi (doanh thu) không làm hỏng cả trang; Thử lại', (tester) async {
      app.backend.revenueFails = true;
      await openStats(tester);
      expect(find.text('2.410.000đ'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);

      app.backend.revenueFails = false;
      await tap(tester, find.text('Thử lại'));
      expect(find.byType(LineChart), findsOneWidget);
    });

    testWidgets('màn rộng: 4 thẻ một hàng, biểu đồ xếp 2 cột', (tester) async {
      await openStats(tester, size: const Size(1300, 1400));
      final revenue = tester.getTopLeft(find.text('Trung bình / đơn'));
      final cancel = tester.getTopLeft(find.text('Tỷ lệ hủy'));
      expect(revenue.dy, cancel.dy);
      expect(tester.getTopLeft(find.byType(LineChart)).dx, lessThan(tester.getTopLeft(find.byType(BarChart)).dx));
    });
  });

  group('Quản trị người dùng', () {
    testWidgets('chỉ admin có tab Người dùng', (tester) async {
      await app.pump(tester, signedIn: staff);
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('Người dùng')), findsNothing);
    });

    testWidgets('tìm → chi tiết → đổi vai trò → khóa; danh sách cập nhật', (tester) async {
      await app.pump(tester, signedIn: admin, size: const Size(420, 1200));
      await tap(tester, find.descendant(of: find.byType(NavigationBar), matching: find.text('Người dùng')));
      expect(find.text('3 tài khoản'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '0023410001');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('1 tài khoản'), findsOneWidget);

      await tap(tester, find.text('Nguyễn Văn An'));
      expect(find.byType(UserDetailScreen), findsOneWidget);
      expect(find.text('245.000đ'), findsOneWidget);

      await tap(tester, segment('Nhân viên'));
      expect(find.text('Đổi vai trò thành "Nhân viên căn-tin"?'), findsOneWidget);
      await tap(tester, find.text('Đổi vai trò'));
      expect(app.backend.profiles['uid-sv01']!['role'], 'staff');
      expect(find.text('Đã đổi vai trò thành Nhân viên căn-tin.'), findsOneWidget);
      await settleSnackBars(tester);

      await tap(tester, find.text('Khóa tài khoản'));
      await tap(tester, find.widgetWithText(FilledButton, 'Khóa'));
      expect(app.backend.locked, contains('uid-sv01'));
      expect(find.text('Mở khóa tài khoản'), findsOneWidget);
      expect(find.text('Đã khóa tài khoản.'), findsOneWidget, reason: 'báo thành công, không báo lỗi');
      await settleSnackBars(tester);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Đã khóa'), findsWidgets);
      expect(find.text('Nhân viên'), findsWidgets);
    });

    testWidgets('lọc tài khoản bị khóa; tài khoản của chính mình không sửa được', (tester) async {
      app.backend.locked.add('uid-staff');
      await app.pump(tester, signedIn: admin, size: const Size(420, 1200));
      await tap(tester, find.descendant(of: find.byType(NavigationBar), matching: find.text('Người dùng')));
      await tap(tester, find.widgetWithText(FilterChip, 'Đã khóa'));
      expect(find.text('1 tài khoản'), findsOneWidget);
      expect(find.text('staff@smartcanteen.vn'), findsOneWidget);

      await tap(tester, find.widgetWithText(FilterChip, 'Đã khóa'));
      await tap(tester, find.widgetWithText(ChoiceChip, 'Quản trị'));
      await tap(tester, find.text('admin@smartcanteen.vn'));
      expect(find.textContaining('không thể tự đổi vai trò'), findsOneWidget);
      expect(find.text('Khóa tài khoản'), findsNothing);
      expect((tester.widget(segmented.first) as SegmentedButton).onSelectionChanged, isNull);
    });
  });
}
