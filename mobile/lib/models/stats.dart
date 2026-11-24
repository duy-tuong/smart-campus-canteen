import '../core/utils/vn_time.dart';
import 'enums.dart';

/// Ngày "yyyy-MM-dd" (DateOnly của backend) → DateTime UTC 00:00 của ngày đó (lịch Việt Nam).
DateTime _day(Object? value) => DateTime.parse('${value as String}T00:00:00Z');

int _int(Object? v) => (v as num?)?.toInt() ?? 0;
double _double(Object? v) => (v as num?)?.toDouble() ?? 0;

/// Khoảng ngày thống kê (theo lịch Việt Nam, gồm cả hai đầu).
class StatsRange {
  const StatsRange(this.from, this.to);

  /// [days] ngày gần nhất, tính cả hôm nay.
  factory StatsRange.lastDays(int days, {DateTime? now}) {
    final today = VnTime.today(now: now);
    return StatsRange(today.subtract(Duration(days: days - 1)), today);
  }

  final DateTime from;
  final DateTime to;

  int get days => to.difference(from).inDays + 1;

  Map<String, Object?> get query => {'from': VnTime.isoDate(from), 'to': VnTime.isoDate(to)};

  /// Cách nhóm doanh thu hợp lý: ≤ 31 ngày theo ngày, ≤ 120 ngày theo tuần, còn lại theo tháng.
  RevenueGroup get defaultGroup => days <= 31
      ? RevenueGroup.day
      : days <= 120
      ? RevenueGroup.week
      : RevenueGroup.month;

  /// "16/11/2026" hoặc "18/10 – 16/11/2026".
  String get label {
    String d(DateTime x, {bool year = true}) =>
        '${x.day.toString().padLeft(2, '0')}/${x.month.toString().padLeft(2, '0')}${year ? '/${x.year}' : ''}';
    if (days == 1) return d(from);
    return '${d(from, year: from.year != to.year)} – ${d(to)}';
  }

  @override
  bool operator ==(Object other) => other is StatsRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

enum RevenueGroup {
  day('Ngày'),
  week('Tuần'),
  month('Tháng');

  const RevenueGroup(this.label);
  final String label;
}

enum TopFoodSort {
  quantity('Số lượng'),
  revenue('Doanh thu');

  const TopFoodSort(this.label);
  final String label;
}

class PaymentMethodStat {
  const PaymentMethodStat({required this.method, required this.orders, required this.revenue});

  factory PaymentMethodStat.fromJson(Map<String, dynamic> json) => PaymentMethodStat(
    method: PaymentMethod.fromJson(json['method']),
    orders: _int(json['orders']),
    revenue: _int(json['revenue']),
  );

  final PaymentMethod method;
  final int orders;
  final int revenue;
}

/// GET /api/stats/overview — doanh thu = đơn đã HOÀN THÀNH, sau giảm giá.
class StatsOverview {
  const StatsOverview({
    required this.range,
    required this.revenue,
    required this.completedOrders,
    required this.cancelledOrders,
    required this.cancelRate,
    required this.averageOrderValue,
    required this.itemsSold,
    required this.discountTotal,
    required this.uniqueCustomers,
    required this.byPaymentMethod,
    required this.refundOrders,
    required this.refundAmount,
    required this.previousRange,
    required this.previousRevenue,
    required this.previousCompletedOrders,
    required this.revenueChangePercent,
  });

  factory StatsOverview.fromJson(Map<String, dynamic> json) {
    final previous = json['previous'] as Map<String, dynamic>? ?? const {};
    final refunds = json['refunds'] as Map<String, dynamic>? ?? const {};
    return StatsOverview(
      range: StatsRange(_day(json['from']), _day(json['to'])),
      revenue: _int(json['revenue']),
      completedOrders: _int(json['completedOrders']),
      cancelledOrders: _int(json['cancelledOrders']),
      cancelRate: _double(json['cancelRate']),
      averageOrderValue: _int(json['averageOrderValue']),
      itemsSold: _int(json['itemsSold']),
      discountTotal: _int(json['discountTotal']),
      uniqueCustomers: _int(json['uniqueCustomers']),
      byPaymentMethod: (json['byPaymentMethod'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PaymentMethodStat.fromJson)
          .toList(),
      refundOrders: _int(refunds['orders']),
      refundAmount: _int(refunds['amount']),
      previousRange: previous['from'] == null ? null : StatsRange(_day(previous['from']), _day(previous['to'])),
      previousRevenue: _int(previous['revenue']),
      previousCompletedOrders: _int(previous['completedOrders']),
      revenueChangePercent: (previous['revenueChangePercent'] as num?)?.toDouble(),
    );
  }

  final StatsRange range;
  final int revenue;
  final int completedOrders;
  final int cancelledOrders;

  /// % đơn bị hủy trên tổng đơn đã kết thúc.
  final double cancelRate;
  final int averageOrderValue;
  final int itemsSold;
  final int discountTotal;
  final int uniqueCustomers;
  final List<PaymentMethodStat> byPaymentMethod;

  /// Đơn đã thanh toán nhưng bị hủy → cần hoàn tiền.
  final int refundOrders;
  final int refundAmount;

  final StatsRange? previousRange;
  final int previousRevenue;
  final int previousCompletedOrders;

  /// null nếu kỳ trước không có doanh thu.
  final double? revenueChangePercent;

  /// % thay đổi số đơn so với kỳ trước (null nếu kỳ trước = 0).
  double? get ordersChangePercent =>
      previousCompletedOrders == 0 ? null : (completedOrders - previousCompletedOrders) * 100 / previousCompletedOrders;

  bool get isEmpty => completedOrders == 0 && cancelledOrders == 0;
}

class RevenuePoint {
  const RevenuePoint({required this.period, required this.label, required this.revenue, required this.orders});

  factory RevenuePoint.fromJson(Map<String, dynamic> json) => RevenuePoint(
    period: _day(json['period']),
    label: json['label'] as String? ?? '',
    revenue: _int(json['revenue']),
    orders: _int(json['orders']),
  );

  final DateTime period;

  /// Nhãn do backend tạo: "16/11", "09/11–15/11", "11/2026".
  final String label;
  final int revenue;
  final int orders;
}

/// GET /api/stats/revenue — kỳ không có đơn = 0 (chuỗi liên tục, vẽ được ngay).
class RevenueSeries {
  const RevenueSeries({
    required this.group,
    required this.totalRevenue,
    required this.totalOrders,
    required this.points,
  });

  factory RevenueSeries.fromJson(Map<String, dynamic> json) => RevenueSeries(
    group: RevenueGroup.values.firstWhere((g) => g.name == json['groupBy'], orElse: () => RevenueGroup.day),
    totalRevenue: _int(json['totalRevenue']),
    totalOrders: _int(json['totalOrders']),
    points: (json['points'] as List? ?? const []).whereType<Map<String, dynamic>>().map(RevenuePoint.fromJson).toList(),
  );

  final RevenueGroup group;
  final int totalRevenue;
  final int totalOrders;
  final List<RevenuePoint> points;
}

class TopFood {
  const TopFood({
    required this.foodId,
    required this.name,
    required this.categoryName,
    required this.quantity,
    required this.revenue,
    required this.averageRating,
    required this.ratingCount,
  });

  factory TopFood.fromJson(Map<String, dynamic> json) => TopFood(
    foodId: _int(json['foodId']),
    name: json['name'] as String? ?? '',
    categoryName: json['categoryName'] as String? ?? '',
    quantity: _int(json['quantity']),
    revenue: _int(json['revenue']),
    averageRating: _double(json['averageRating']),
    ratingCount: _int(json['ratingCount']),
  );

  final int foodId;
  final String name;
  final String categoryName;
  final int quantity;

  /// Doanh thu gộp (trước giảm giá theo đơn).
  final int revenue;
  final double averageRating;
  final int ratingCount;
}

class HourlyStat {
  const HourlyStat({required this.hour, required this.orders, required this.revenue});

  factory HourlyStat.fromJson(Map<String, dynamic> json) =>
      HourlyStat(hour: _int(json['hour']), orders: _int(json['orders']), revenue: _int(json['revenue']));

  final int hour;
  final int orders;
  final int revenue;
}

class CategoryStat {
  const CategoryStat({
    required this.categoryId,
    required this.name,
    required this.quantity,
    required this.revenue,
    required this.percent,
  });

  factory CategoryStat.fromJson(Map<String, dynamic> json) => CategoryStat(
    categoryId: (json['categoryId'] as num?)?.toInt(),
    name: json['name'] as String? ?? 'Khác',
    quantity: _int(json['quantity']),
    revenue: _int(json['revenue']),
    percent: _double(json['percent']),
  );

  final int? categoryId;
  final String name;
  final int quantity;
  final int revenue;

  /// Tỷ trọng doanh thu (%), tổng = 100.
  final double percent;
}

/// Phần "tổng quan" của bảng thống kê: tải song song 3 API trong một Future.
class StatsSummary {
  const StatsSummary({required this.overview, required this.hourly, required this.categories});

  final StatsOverview overview;
  final List<HourlyStat> hourly;
  final List<CategoryStat> categories;

  /// Giờ đông nhất (null nếu không có đơn).
  HourlyStat? get peakHour {
    HourlyStat? best;
    for (final h in hourly) {
      if (h.orders > 0 && (best == null || h.orders > best.orders)) best = h;
    }
    return best;
  }
}
