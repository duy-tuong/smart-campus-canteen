import '../../models/admin_user.dart';
import '../../models/enums.dart';
import '../../models/paged_result.dart';
import '../../models/stats.dart';
import 'api_client.dart';

/// Thống kê (staff/admin) — mọi khoảng ngày theo lịch Việt Nam (?from=&to=).
class StatsApi {
  StatsApi(this._api);

  final ApiClient _api;

  Future<StatsOverview> overview(StatsRange range) async =>
      StatsOverview.fromJson(await _api.get('/api/stats/overview', query: range.query) as Map<String, dynamic>);

  Future<RevenueSeries> revenue(StatsRange range, RevenueGroup group) async => RevenueSeries.fromJson(
    await _api.get('/api/stats/revenue', query: {...range.query, 'groupBy': group.name}) as Map<String, dynamic>,
  );

  Future<List<TopFood>> topFoods(StatsRange range, {TopFoodSort sortBy = TopFoodSort.quantity, int limit = 10}) async =>
      (await _api.get('/api/stats/top-foods', query: {...range.query, 'sortBy': sortBy.name, 'limit': limit}) as List)
          .whereType<Map<String, dynamic>>()
          .map(TopFood.fromJson)
          .toList();

  Future<List<HourlyStat>> hourly(StatsRange range) async =>
      (await _api.get('/api/stats/hourly', query: range.query) as List)
          .whereType<Map<String, dynamic>>()
          .map(HourlyStat.fromJson)
          .toList();

  Future<List<CategoryStat>> categories(StatsRange range) async =>
      (await _api.get('/api/stats/categories', query: range.query) as List)
          .whereType<Map<String, dynamic>>()
          .map(CategoryStat.fromJson)
          .toList();

  /// Tổng quan + giờ cao điểm + danh mục: gọi SONG SONG (Future.wait) — một lỗi là cả khối báo lỗi.
  Future<StatsSummary> summary(StatsRange range) async {
    final results = await Future.wait<Object>([overview(range), hourly(range), categories(range)]);
    return StatsSummary(
      overview: results[0] as StatsOverview,
      hourly: results[1] as List<HourlyStat>,
      categories: results[2] as List<CategoryStat>,
    );
  }
}

/// Quản trị tài khoản (chỉ admin).
class AdminApi {
  AdminApi(this._api);

  final ApiClient _api;

  /// Tìm theo họ tên (không dấu), email hoặc MSSV; lọc vai trò / trạng thái; mới nhất trước.
  Future<PagedResult<AdminUser>> users({
    String? search,
    UserRole? role,
    bool? isActive,
    int page = 1,
    int pageSize = 20,
  }) async => PagedResult.fromJson(
    await _api.get(
          '/api/admin/users',
          query: {
            'search': (search == null || search.trim().isEmpty) ? null : search.trim(),
            'role': role?.name,
            'isActive': isActive,
            'page': page,
            'pageSize': pageSize,
          },
        )
        as Map<String, dynamic>,
    AdminUser.fromJson,
  );

  Future<AdminUser> user(String id) async =>
      AdminUser.fromJson(await _api.get('/api/admin/users/$id') as Map<String, dynamic>);

  /// 403 CANNOT_MODIFY_SELF nếu tự đổi vai trò của mình.
  Future<AdminUser> changeRole(String id, UserRole role) async => AdminUser.fromJson(
    await _api.patch('/api/admin/users/$id/role', body: {'role': role.name}) as Map<String, dynamic>,
  );

  /// Khóa (isActive=false) / mở khóa — khóa cả đăng nhập Firebase, có hiệu lực ngay.
  Future<AdminUser> setActive(String id, bool isActive) async => AdminUser.fromJson(
    await _api.patch('/api/admin/users/$id/status', body: {'isActive': isActive}) as Map<String, dynamic>,
  );
}
