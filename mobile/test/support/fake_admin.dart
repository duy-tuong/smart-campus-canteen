import 'dart:convert';

import 'package:http/http.dart' as http;

import 'fakes.dart';

/// Phần "thống kê & quản trị tài khoản" của backend giả.
mixin FakeAdmin {
  Map<String, Map<String, Object?>> get profiles;
  Set<String> get locked;

  /// Query của mọi lần gọi /api/stats/* : (endpoint, query).
  final List<(String, Map<String, String>)> statsRequests = [];

  /// Bật để mọi endpoint thống kê trả số 0 (khoảng không có đơn).
  bool statsEmpty = false;

  /// Bật để /api/stats/revenue lỗi 500 (thử lỗi từng khối).
  bool revenueFails = false;

  http.Response? handleAdmin(http.Request request, String uid) {
    final path = request.url.path;
    final q = request.url.queryParameters;

    if (path.startsWith('/api/stats/')) {
      final endpoint = path.substring('/api/stats/'.length);
      statsRequests.add((endpoint, q));
      return switch (endpoint) {
        'overview' => jsonResponse(_overview(q), 200),
        'revenue' =>
          revenueFails
              ? problem(500, 'INTERNAL_ERROR', 'Lỗi máy chủ.')
              : jsonResponse({
                  'from': q['from'],
                  'to': q['to'],
                  'groupBy': q['groupBy'],
                  'totalRevenue': statsEmpty ? 0 : 2400000,
                  'totalOrders': statsEmpty ? 0 : 42,
                  'points': [
                    for (var d = 10; d <= 16; d++)
                      {
                        'period': '2026-11-$d',
                        'label': '$d/11',
                        'revenue': statsEmpty ? 0 : 300000 + d * 1000,
                        'orders': statsEmpty ? 0 : 6,
                      },
                  ],
                }, 200),
        'top-foods' => jsonResponse([
          if (!statsEmpty) ...[
            _top(12, 'Trà sữa trân châu', 'Nước uống', q['sortBy'] == 'revenue' ? 30 : 134, 4112000),
            _top(1, 'Cơm gà xối mỡ', 'Cơm', 129, q['sortBy'] == 'revenue' ? 9659000 : 4659000),
          ],
        ], 200),
        'hourly' => jsonResponse([
          for (var h = 0; h < 24; h++)
            {
              'hour': h,
              'orders': statsEmpty || h < 7 || h > 19 ? 0 : (h == 11 ? 85 : 20),
              'revenue': statsEmpty || h < 7 || h > 19 ? 0 : 1000000,
            },
        ], 200),
        'categories' => jsonResponse([
          if (!statsEmpty) ...[
            {'categoryId': 1, 'name': 'Cơm', 'quantity': 357, 'revenue': 13292000, 'percent': 64.3},
            {'categoryId': 3, 'name': 'Nước uống', 'quantity': 416, 'revenue': 7381000, 'percent': 35.7},
          ],
        ], 200),
        _ => null,
      };
    }

    if (path == '/api/admin/users') {
      final search = (q['search'] ?? '').toLowerCase();
      final list =
          profiles.values
              .map(_withStatus)
              .where(
                (p) =>
                    search.isEmpty ||
                    (p['fullName']! as String).toLowerCase().contains(search) ||
                    (p['email']! as String).contains(search) ||
                    ((p['studentCode'] as String?)?.contains(search) ?? false),
              )
              .where((p) => q['role'] == null || p['role'] == q['role'])
              .where((p) => q['isActive'] == null || p['isActive'] == (q['isActive'] == 'true'))
              .toList()
            ..sort((a, b) => (a['email']! as String).compareTo(b['email']! as String));
      return jsonResponse({
        'items': list,
        'page': 1,
        'pageSize': 20,
        'totalCount': list.length,
        'totalPages': 1,
        'hasNext': false,
      }, 200);
    }
    final user = RegExp(r'^/api/admin/users/([^/]+)(/role|/status)?$').firstMatch(path);
    if (user != null) {
      final id = user.group(1)!;
      final profile = profiles[id];
      if (profile == null) return problem(404, 'NOT_FOUND', 'Không tìm thấy người dùng.');
      if (request.method == 'PATCH') {
        if (id == uid) return problem(403, 'CANNOT_MODIFY_SELF', 'Không thể tự thay đổi tài khoản của mình.');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (user.group(2) == '/role') {
          profile['role'] = body['role'];
        } else {
          final active = body['isActive'] as bool;
          active ? locked.remove(id) : locked.add(id);
        }
      }
      return jsonResponse({
        ..._withStatus(profile),
        'updatedAt': '2026-11-16T02:00:00Z',
        'orderCount': 7,
        'completedOrderCount': 5,
        'totalSpent': 245000,
      }, 200);
    }
    return null;
  }

  Map<String, Object?> _withStatus(Map<String, Object?> p) => {...p, 'isActive': !locked.contains(p['id'])};

  Map<String, Object?> _overview(Map<String, String> q) => {
    'from': q['from'],
    'to': q['to'],
    'revenue': statsEmpty ? 0 : 2410000,
    'completedOrders': statsEmpty ? 0 : 42,
    'cancelledOrders': statsEmpty ? 0 : 3,
    'cancelRate': statsEmpty ? 0 : 6.7,
    'averageOrderValue': statsEmpty ? 0 : 57381,
    'itemsSold': statsEmpty ? 0 : 88,
    'discountTotal': statsEmpty ? 0 : 35000,
    'uniqueCustomers': statsEmpty ? 0 : 9,
    'byPaymentMethod': [
      if (!statsEmpty) ...[
        {'method': 'cash', 'orders': 30, 'revenue': 1700000},
        {'method': 'bankTransfer', 'orders': 12, 'revenue': 710000},
      ],
    ],
    'refunds': {'orders': statsEmpty ? 0 : 1, 'amount': statsEmpty ? 0 : 45000},
    'previous': {
      'from': '2026-11-03',
      'to': '2026-11-09',
      'revenue': statsEmpty ? 0 : 2000000,
      'completedOrders': statsEmpty ? 0 : 48,
      'revenueChangePercent': statsEmpty ? null : 20.5,
    },
  };

  static Map<String, Object?> _top(int id, String name, String category, int quantity, int revenue) => {
    'foodId': id,
    'name': name,
    'categoryName': category,
    'quantity': quantity,
    'revenue': revenue,
    'averageRating': 4.2,
    'ratingCount': 10,
  };
}
