import 'package:campus_canteen/models/admin_user.dart';
import 'package:campus_canteen/models/enums.dart';
import 'package:campus_canteen/models/stats.dart';
import 'package:campus_canteen/screens/staff/stats_charts.dart';
import 'package:flutter_test/flutter_test.dart';

/// Model thống kê / quản trị đọc đúng JSON thật của backend (mẫu lấy từ API đang chạy).
void main() {
  group('StatsRange', () {
    test('7 ngày gần nhất tính theo giờ Việt Nam, gồm cả hôm nay', () {
      // 18:00 UTC ngày 15 = 01:00 sáng 16/11 ở Việt Nam.
      final r = StatsRange.lastDays(7, now: DateTime.utc(2026, 11, 15, 18));
      expect(r.query, {'from': '2026-11-10', 'to': '2026-11-16'});
      expect(r.days, 7);
      expect(r.label, '10/11 – 16/11/2026');
    });

    test('cách nhóm doanh thu mặc định theo độ dài khoảng', () {
      expect(StatsRange.lastDays(30).defaultGroup, RevenueGroup.day);
      expect(StatsRange.lastDays(90).defaultGroup, RevenueGroup.week);
      expect(StatsRange.lastDays(365).defaultGroup, RevenueGroup.month);
      expect(StatsRange.lastDays(1).label, isNot(contains('–')));
    });
  });

  test('overview: số liệu, phương thức thanh toán, so sánh kỳ trước', () {
    final o = StatsOverview.fromJson({
      'from': '2026-10-18',
      'to': '2026-11-16',
      'revenue': 36547300,
      'completedOrders': 648,
      'cancelledOrders': 50,
      'cancelRate': 7.2,
      'averageOrderValue': 56400,
      'itemsSold': 1256,
      'discountTotal': 652700,
      'uniqueCustomers': 10,
      'byPaymentMethod': [
        {'method': 'cash', 'orders': 460, 'revenue': 26526200},
        {'method': 'bankTransfer', 'orders': 188, 'revenue': 10021100},
      ],
      'refunds': {'orders': 0, 'amount': 0},
      'previous': {
        'from': '2026-09-18',
        'to': '2026-10-17',
        'revenue': 390000,
        'completedOrders': 10,
        'revenueChangePercent': 9271.1,
      },
    });
    expect(o.range.days, 30);
    expect(o.byPaymentMethod.last.method, PaymentMethod.bankTransfer);
    expect(o.revenueChangePercent, 9271.1);
    expect(o.ordersChangePercent, closeTo(6380, 0.01));
    expect(o.previousRange!.label, '18/09 – 17/10/2026');
    expect(o.isEmpty, isFalse);
  });

  test('kỳ trước không có doanh thu → % thay đổi null', () {
    final o = StatsOverview.fromJson({
      'from': '2026-11-16',
      'to': '2026-11-16',
      'revenue': 0,
      'completedOrders': 0,
      'cancelledOrders': 0,
      'cancelRate': 0,
      'byPaymentMethod': <Object>[],
      'previous': {'from': '2026-11-15', 'to': '2026-11-15', 'revenue': 0, 'completedOrders': 0},
    });
    expect(o.revenueChangePercent, isNull);
    expect(o.ordersChangePercent, isNull);
    expect(o.isEmpty, isTrue);
  });

  test('revenue, giờ cao điểm', () {
    final s = RevenueSeries.fromJson({
      'groupBy': 'week',
      'totalRevenue': 100,
      'totalOrders': 2,
      'points': [
        {'period': '2026-11-09', 'label': '09/11–15/11', 'revenue': 100, 'orders': 2},
      ],
    });
    expect(s.group, RevenueGroup.week);
    expect(s.points.single.period, DateTime.utc(2026, 11, 9));

    final summary = StatsSummary(
      overview: StatsOverview.fromJson({'from': '2026-11-16', 'to': '2026-11-16', 'previous': <String, Object?>{}}),
      hourly: [for (var h = 0; h < 24; h++) HourlyStat(hour: h, orders: h == 11 ? 9 : (h == 7 ? 3 : 0), revenue: 0)],
      categories: const [],
    );
    expect(summary.peakHour!.hour, 11);
  });

  test('niceStep cho trục: bước tròn 1/2/2,5/5 × 10^n', () {
    expect(niceStep(36547300), 10000000);
    expect(niceStep(85), 25);
    expect(niceStep(0), 1);
  });

  test('AdminUser: bản danh sách không có thống kê, bản chi tiết có', () {
    final u = AdminUser.fromJson({
      'id': 'x',
      'email': 'sv02@smartcanteen.vn',
      'fullName': 'Trần Thị Bình',
      'studentCode': '0023410002',
      'avatarUrl': null,
      'role': 'staff',
      'isActive': false,
      'createdAt': '2026-11-16T09:51:59.688Z',
      'lastLoginAt': null,
    });
    expect((u.role, u.isActive, u.orderCount), (UserRole.staff, false, null));
    expect(u.asProfile.initials, 'BT');
  });
}
