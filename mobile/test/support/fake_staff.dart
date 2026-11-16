import 'dart:convert';

import 'package:http/http.dart' as http;

import 'fakes.dart';

/// Phần "nhân viên căn-tin" của backend giả: chuyển trạng thái đơn, xác nhận thanh toán,
/// quản lý danh mục / món / voucher / đánh giá.
mixin FakeStaffing {
  Map<String, Map<String, Object?>> get orders;
  List<Map<String, Object?>> get foods;
  List<Map<String, Object?>> get categories;
  Map<int, Map<String, Object?>> get reviews;

  /// Lệnh chuyển trạng thái đã nhận: (orderId, status).
  final List<(String, String)> statusChanges = [];

  /// Bật để PATCH status trả 409 (nhân viên khác vừa cập nhật).
  bool statusConflict = false;

  /// rowVersion hiện tại của từng món (mặc định 'AAAA'); đổi giá trị để giả lập người khác vừa sửa.
  final Map<int, String> foodVersions = {};
  final Map<int, List<Map<String, Object?>>> savedGroups = {};
  final Set<int> deletedFoods = {};
  final List<Map<String, Object?>> vouchersAdmin = [];
  int _nextFoodId = 500;
  int _nextCategoryId = 50;

  static const _next = {'received': 'cooking', 'cooking': 'ready', 'ready': 'completed'};

  http.Response? handleStaffing(http.Request request) {
    final path = request.url.path;
    final method = request.method;
    Map<String, dynamic> body() => jsonDecode(request.body) as Map<String, dynamic>;

    // ----- Đơn hàng -----
    final status = RegExp(r'^/api/orders/([^/]+)/status$').firstMatch(path);
    if (status != null && method == 'PATCH') {
      final order = orders[status.group(1)]!;
      final to = body()['status'] as String;
      if (statusConflict) return problem(409, 'CONCURRENCY_CONFLICT', 'Đơn vừa được cập nhật.');
      if (_next[order['status']] != to) {
        return problem(422, 'INVALID_STATUS_TRANSITION', 'Không thể chuyển trạng thái này.');
      }
      if (order['paymentMethod'] == 'bankTransfer' && order['paymentStatus'] != 'paid') {
        return problem(422, 'PAYMENT_REQUIRED', 'Đơn chuyển khoản chưa được thanh toán — chưa thể chế biến.');
      }
      order['status'] = to;
      statusChanges.add((order['id']! as String, to));
      return jsonResponse(order, 200);
    }
    final confirm = RegExp(r'^/api/orders/([^/]+)/payment/confirm$').firstMatch(path);
    if (confirm != null) {
      final order = orders[confirm.group(1)]!..['paymentStatus'] = 'paid';
      return jsonResponse(order, 200);
    }

    // ----- Danh mục -----
    if (path == '/api/categories' && method == 'POST') {
      final c = {...body(), 'id': _nextCategoryId++, 'foodCount': 0};
      categories.add(c);
      return jsonResponse(c, 201);
    }
    if (path == '/api/categories/order' && method == 'PUT') {
      for (final item in (body()['items'] as List).cast<Map<String, dynamic>>()) {
        categories.firstWhere((c) => c['id'] == item['id'])['sortOrder'] = item['sortOrder'];
      }
      return jsonResponse(categories, 200);
    }
    final category = RegExp(r'^/api/categories/(\d+)$').firstMatch(path);
    if (category != null) {
      final id = int.parse(category.group(1)!);
      final c = categories.firstWhere((c) => c['id'] == id);
      if (method == 'DELETE') {
        if (foods.any((f) => f['categoryId'] == id && !deletedFoods.contains(f['id']))) {
          return problem(409, 'CATEGORY_NOT_EMPTY', 'Danh mục còn món — hãy chuyển hoặc xóa món trước.');
        }
        categories.remove(c);
        return http.Response('', 204);
      }
      c.addAll(body());
      return jsonResponse(c, 200);
    }

    // ----- Món ăn -----
    if (path == '/api/foods' && method == 'POST') {
      final b = body();
      final id = _nextFoodId++;
      final food = FakeBackend.foodJson(id, b['name'] as String, b['price'] as int, categoryId: b['categoryId'] as int);
      foods.add(food);
      savedGroups[id] = (b['optionGroups'] as List).cast<Map<String, Object?>>();
      return jsonResponse({
        ...food,
        'description': b['description'],
        'optionGroups': [],
        'rowVersion': 'AAAA',
        'createdAt': '2026-11-16T00:00:00Z',
        'updatedAt': '2026-11-16T00:00:00Z',
        'dailyLimit': b['dailyLimit'],
      }, 201);
    }
    final food = RegExp(r'^/api/foods/(\d+)(/option-groups|/availability|/image)?$').firstMatch(path);
    if (food != null && method != 'GET') {
      final id = int.parse(food.group(1)!);
      final f = foods.firstWhere((f) => f['id'] == id);
      Map<String, Object?> detail() => {
        ...f,
        'description': 'Mô tả',
        'optionGroups': const [],
        'rowVersion': foodVersions[id] ?? 'AAAA',
        'dailyLimit': null,
        'createdAt': '2026-11-16T00:00:00Z',
        'updatedAt': '2026-11-16T00:00:00Z',
      };
      switch (food.group(2)) {
        case '/availability':
          f['isAvailable'] = body()['isAvailable'];
          return jsonResponse(detail(), 200);
        case '/option-groups':
          savedGroups[id] = (body()['groups'] as List).cast<Map<String, Object?>>();
          return jsonResponse(detail(), 200);
        case '/image':
          f['imageUrl'] = 'http://api.test/uploads/foods/$id.png';
          return jsonResponse(detail(), 200);
        default:
          if (method == 'DELETE') {
            deletedFoods.add(id);
            foods.remove(f);
            return http.Response('', 204);
          }
          final b = body();
          if (b['rowVersion'] != (foodVersions[id] ?? 'AAAA')) {
            return problem(409, 'CONCURRENCY_CONFLICT', 'Dữ liệu vừa được người khác cập nhật.');
          }
          f
            ..['name'] = b['name']
            ..['price'] = b['price']
            ..['isAvailable'] = b['isAvailable'];
          return jsonResponse(detail(), 200);
      }
    }

    // ----- Voucher -----
    if (path == '/api/admin/vouchers' && method == 'GET') {
      return jsonResponse({
        'items': vouchersAdmin,
        'page': 1,
        'pageSize': 50,
        'totalCount': vouchersAdmin.length,
        'totalPages': 1,
        'hasNext': false,
      }, 200);
    }
    if (path == '/api/admin/vouchers' && method == 'POST') {
      final b = body();
      if (vouchersAdmin.any((v) => v['code'] == b['code'])) {
        return problem(409, 'VOUCHER_CODE_TAKEN', 'Mã đã tồn tại.');
      }
      final v = {
        ...b,
        'id': vouchersAdmin.length + 1,
        'usedCount': 0,
        'orderCount': 0,
        'rowVersion': 'V1',
        'createdAt': '2026-11-16T00:00:00Z',
        'updatedAt': '2026-11-16T00:00:00Z',
      };
      vouchersAdmin.add(v);
      return jsonResponse(v, 201);
    }
    final voucher = RegExp(r'^/api/admin/vouchers/(\d+)(/status)?$').firstMatch(path);
    if (voucher != null) {
      final v = vouchersAdmin.firstWhere((v) => v['id'] == int.parse(voucher.group(1)!));
      if (method == 'DELETE') {
        vouchersAdmin.remove(v);
        return http.Response('', 204);
      }
      v.addAll(body());
      return jsonResponse(v, 200);
    }

    // ----- Đánh giá -----
    if (path == '/api/admin/reviews') {
      final q = request.url.queryParameters;
      final list = reviews.values
          .where((r) => q['hasReply'] == null || (r['staffReply'] != null) == (q['hasReply'] == 'true'))
          .where((r) => q['isHidden'] == null || r['isHidden'] == (q['isHidden'] == 'true'))
          .toList();
      return jsonResponse({
        'items': list,
        'page': 1,
        'pageSize': 20,
        'totalCount': list.length,
        'totalPages': 1,
        'hasNext': false,
      }, 200);
    }
    final review = RegExp(r'^/api/admin/reviews/(\d+)/(visibility|reply)$').firstMatch(path);
    if (review != null) {
      final r = reviews[int.parse(review.group(1)!)]!;
      if (review.group(2) == 'reply') {
        r['staffReply'] = method == 'DELETE' ? null : body()['reply'];
      } else {
        final b = body();
        r
          ..['isHidden'] = b['isHidden']
          ..['hiddenReason'] = b['reason'];
      }
      return jsonResponse(r, 200);
    }
    return null;
  }
}
