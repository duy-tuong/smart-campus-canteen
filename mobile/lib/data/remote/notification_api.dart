import '../../models/live.dart';
import 'api_client.dart';

class NotificationPage {
  const NotificationPage({required this.items, required this.page, required this.hasNext, required this.unreadCount});

  final List<AppNotification> items;
  final int page;
  final bool hasNext;
  final int unreadCount;
}

/// REST: thông báo (bản lâu dài trên SQL Server) — đánh dấu đã đọc.
class NotificationApi {
  NotificationApi(this._api);

  final ApiClient _api;

  Future<NotificationPage> list({int page = 1, int pageSize = 20}) async {
    final json =
        await _api.get('/api/notifications', query: {'page': page, 'pageSize': pageSize}) as Map<String, dynamic>;
    final total = (json['totalCount'] as num?)?.toInt() ?? 0;
    final size = (json['pageSize'] as num?)?.toInt() ?? pageSize;
    return NotificationPage(
      items: (json['items'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AppNotification.fromJson)
          .toList(),
      page: page,
      hasNext: page * size < total,
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// Backend cập nhật cả SQL Server lẫn Firebase → danh sách realtime tự đổi.
  Future<void> markRead(int id) => _api.patch('/api/notifications/$id/read');

  Future<int> markAllRead() async =>
      ((await _api.post('/api/notifications/read-all') as Map<String, dynamic>?)?['updated'] as num?)?.toInt() ?? 0;
}
