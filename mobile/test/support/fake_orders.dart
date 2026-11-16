import 'dart:convert';

import 'package:http/http.dart' as http;

import 'fakes.dart';

/// Phần "đặt món" của backend giả: thông tin căn-tin, báo giá, voucher, tạo đơn (Idempotency-Key), thanh toán.
mixin FakeOrdering {
  List<Map<String, Object?>> get foods;
  List<Map<String, Object?>> groupsOf(int foodId);

  bool canteenOpen = true;
  bool bankTransferEnabled = true;

  /// Lần POST /api/orders kế tiếp: máy chủ VẪN tạo đơn nhưng câu trả lời bị mất (mạng rớt).
  bool dropNextCreateResponse = false;

  /// Đơn đã tạo theo Idempotency-Key (gửi lại cùng key → trả lại đơn cũ).
  final Map<String, Map<String, Object?>> ordersByKey = {};
  final Map<String, Map<String, Object?>> orders = {};
  final List<Map<String, dynamic>> createdBodies = [];
  final List<String> idempotencyKeys = [];

  /// Đơn chuyển khoản trong tập này được coi là đã trả tiền khi app hỏi lại.
  final Set<String> paidOrderIds = {};

  final Set<int> readNotificationIds = {};
  int readAllCalls = 0;

  /// Nhân viên căn-tin đổi trạng thái đơn (ghi thêm một bước vào dòng thời gian).
  void setStatus(String id, String status, {String? cancelReason, String at = '2026-11-16T03:10:00Z'}) {
    final order = orders[id]!;
    (order['history']! as List).add({
      'fromStatus': order['status'],
      'toStatus': status,
      'changedByName': 'Căn-tin',
      'changedAt': at,
    });
    order['status'] = status;
    order['canCancel'] = status == 'received';
    if (cancelReason != null) order['cancelReason'] = cancelReason;
  }

  /// Thêm sẵn một đơn (như đã đặt từ trước) để thử màn lịch sử / theo dõi.
  Map<String, Object?> seedOrder({
    String status = 'received',
    String paymentMethod = 'cash',
    String createdAt = '2026-11-16T03:00:00Z',
    int foodId = 1,
    int quantity = 1,
  }) {
    final body = <String, dynamic>{
      'items': [
        {'foodId': foodId, 'quantity': quantity, 'optionIds': <int>[], 'note': null},
      ],
      'paymentMethod': paymentMethod,
      'voucherCode': null,
      'pickupTime': null,
      'note': null,
    };
    final id = 'order-${orders.length + 1}';
    final order = _orderJson(id, 'uid-sv01', body, quoteFor(body))
      ..['createdAt'] = createdAt
      ..['status'] = status
      ..['canCancel'] = status == 'received';
    orders[id] = order;
    return order;
  }

  static Map<String, Object?> _summary(Map<String, Object?> o) => {
    'id': o['id'],
    'pickupCode': o['pickupCode'],
    'status': o['status'],
    'paymentMethod': o['paymentMethod'],
    'paymentStatus': o['paymentStatus'],
    'totalAmount': o['totalAmount'],
    'totalItems': o['totalItems'],
    'itemsPreview': [
      for (final i in (o['items']! as List).cast<Map<String, Object?>>()) '${i['foodName']} ×${i['quantity']}',
    ].join(', '),
    'customerName': 'Nguyễn Văn An',
    'createdAt': o['createdAt'],
    'pickupTime': o['pickupTime'],
  };

  static const vouchers = [
    {
      'code': 'GIAM10',
      'description': 'Giảm 10% cho đơn từ 30.000đ',
      'discountType': 'percent',
      'discountValue': 10,
      'maxDiscount': 15000,
      'minOrderAmount': 30000,
      'endAt': '2026-12-31T16:59:59Z',
      'remainingForMe': 2,
    },
    {
      'code': 'BIGSALE',
      'description': 'Giảm 20.000đ cho đơn từ 200.000đ',
      'discountType': 'fixed',
      'discountValue': 20000,
      'maxDiscount': null,
      'minOrderAmount': 200000,
      'endAt': '2026-12-31T16:59:59Z',
      'remainingForMe': null,
    },
  ];

  Map<String, Object?> quoteFor(Map<String, dynamic> body) {
    final lines = <Map<String, Object?>>[];
    final errors = <Map<String, Object?>>[];
    var subtotal = 0;
    var totalItems = 0;
    for (final (index, raw) in (body['items'] as List).cast<Map<String, dynamic>>().indexed) {
      final foodId = raw['foodId'] as int;
      final quantity = raw['quantity'] as int;
      final food = foods.firstWhere((f) => f['id'] == foodId);
      final optionIds = (raw['optionIds'] as List).cast<int>();
      final options = [
        for (final g in groupsOf(foodId))
          for (final o in (g['options'] as List).cast<Map<String, Object?>>())
            if (optionIds.contains(o['id']))
              {'optionId': o['id'], 'groupName': g['name'], 'optionName': o['name'], 'extraPrice': o['extraPrice']},
      ];
      final optionsPrice = options.fold<int>(0, (sum, o) => sum + (o['extraPrice'] as int));
      final unit = food['price'] as int;
      final remaining = food['remainingToday'];
      if (food['isSoldOut'] == true) {
        errors.add({
          'index': index,
          'foodId': foodId,
          'code': 'ITEM_SOLD_OUT',
          'message': '${food['name']} đã hết suất hôm nay.',
          'remaining': 0,
        });
      } else if (remaining is int && quantity > remaining) {
        errors.add({
          'index': index,
          'foodId': foodId,
          'code': 'ITEM_SOLD_OUT',
          'message': 'Chỉ còn $remaining suất.',
          'remaining': remaining,
        });
      }
      final lineTotal = (unit + optionsPrice) * quantity;
      subtotal += lineTotal;
      totalItems += quantity;
      lines.add({
        'index': index,
        'foodId': foodId,
        'foodName': food['name'],
        'imageUrl': null,
        'unitPrice': unit,
        'optionsPrice': optionsPrice,
        'quantity': quantity,
        'lineTotal': lineTotal,
        'note': raw['note'],
        'options': options,
      });
    }

    Map<String, Object?>? voucher;
    var discount = 0;
    final code = body['voucherCode'] as String?;
    if (code != null) {
      final v = vouchers.where((v) => v['code'] == code).firstOrNull;
      if (v == null) {
        voucher = _voucher(code, false, 0, 'VOUCHER_INVALID', 'Mã giảm giá không tồn tại.');
      } else if (subtotal < (v['minOrderAmount'] as int)) {
        voucher = _voucher(code, false, 0, 'VOUCHER_MIN_ORDER', 'Đơn chưa đủ giá trị tối thiểu.');
      } else {
        discount = v['discountType'] == 'percent'
            ? subtotal * (v['discountValue'] as int) ~/ 100
            : v['discountValue'] as int;
        final max = v['maxDiscount'];
        if (max is int && discount > max) discount = max;
        voucher = _voucher(code, true, discount, null, 'Áp dụng thành công.');
      }
    }
    return {
      'lines': lines,
      'errors': errors,
      'totalItems': totalItems,
      'subtotal': subtotal,
      'voucher': voucher,
      'discountAmount': discount,
      'totalAmount': subtotal - discount,
      'canOrder': errors.isEmpty,
    };
  }

  static Map<String, Object?> _voucher(String code, bool valid, int discount, String? error, String message) => {
    'code': code,
    'isValid': valid,
    'discount': discount,
    'errorCode': error,
    'message': message,
  };

  Map<String, Object?> _orderJson(String id, String uid, Map<String, dynamic> body, Map<String, Object?> quote) {
    final transfer = body['paymentMethod'] == 'bankTransfer';
    final total = quote['totalAmount'];
    return {
      'id': id,
      'pickupCode': 'A${(orders.length + 1).toString().padLeft(3, '0')}',
      'pickupDate': '2026-11-16',
      'status': 'received',
      'paymentMethod': body['paymentMethod'],
      'paymentStatus': 'pending',
      'subtotal': quote['subtotal'],
      'discountAmount': quote['discountAmount'],
      'totalAmount': total,
      'totalItems': quote['totalItems'],
      'voucherCode': body['voucherCode'],
      'note': body['note'],
      'pickupTime': body['pickupTime'],
      'estimatedReadyAt': null,
      'createdAt': '2026-11-16T03:00:00Z',
      'updatedAt': '2026-11-16T03:00:00Z',
      'customer': {'id': uid, 'fullName': 'Nguyễn Văn An'},
      'items': [
        for (final l in (quote['lines'] as List).cast<Map<String, Object?>>())
          {
            'id': l['index'],
            'foodId': l['foodId'],
            'foodName': l['foodName'],
            'unitPrice': l['unitPrice'],
            'optionsPrice': l['optionsPrice'],
            'quantity': l['quantity'],
            'lineTotal': l['lineTotal'],
            'note': l['note'],
            'options': l['options'],
          },
      ],
      'history': <Map<String, Object?>>[
        {'fromStatus': null, 'toStatus': 'received', 'changedByName': 'An', 'changedAt': '2026-11-16T03:00:00Z'},
      ],
      'payment': {
        'method': body['paymentMethod'],
        'status': 'pending',
        'amount': total,
        'paidAt': null,
        'checkoutUrl': transfer ? 'https://pay.payos.vn/web/test' : null,
        'qrCode': transfer ? '00020101021238570010A000000727' : null,
        'expiresAt': transfer ? DateTime.now().toUtc().add(const Duration(minutes: 15)).toIso8601String() : null,
        'transferContent': transfer ? 'SC0000001' : null,
        'bankBin': transfer ? '970422' : null,
        'bankAccountNumber': transfer ? '0123456789' : null,
        'bankAccountName': transfer ? 'CANTEEN DEMO' : null,
      },
      'canCancel': true,
      'allowedNextStatuses': const <String>[],
    };
  }

  http.Response? handleOrdering(http.Request request, String uid) {
    final path = request.url.path;
    if (path == '/api/canteen/info') {
      return jsonResponse({
        'openTime': '06:30',
        'closeTime': '23:59',
        'isOpen': canteenOpen,
        'serverTime': DateTime.now().toUtc().toIso8601String(),
        'minPickupLeadMinutes': 10,
        'unpaidTransferTimeoutMinutes': 15,
        'maxActiveOrdersPerUser': 3,
        'maxLinesPerOrder': 20,
        'bankTransferEnabled': bankTransferEnabled,
      }, 200);
    }
    if (path == '/api/vouchers/available') return jsonResponse(vouchers, 200);
    if (path == '/api/orders/quote') {
      return jsonResponse(quoteFor(jsonDecode(request.body) as Map<String, dynamic>), 200);
    }

    if (path == '/api/orders' && request.method == 'POST') {
      final key = request.headers['Idempotency-Key'];
      if (key == null) return problem(400, 'VALIDATION_ERROR', 'Thiếu Idempotency-Key.');
      idempotencyKeys.add(key);
      if (!canteenOpen) return problem(422, 'CANTEEN_CLOSED', 'Căn-tin chỉ nhận đơn từ 06:30 đến 19:00.');
      final existing = ordersByKey[key];
      if (existing != null) return jsonResponse(existing, 200);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final quote = quoteFor(body);
      if (quote['canOrder'] != true) {
        return jsonResponse({
          'status': 422,
          'code': 'ORDER_ITEMS_INVALID',
          'detail': 'Giỏ hàng có món không đặt được.',
          'items': quote['errors'],
        }, 422);
      }
      createdBodies.add(body);
      final id = 'order-${orders.length + 1}';
      final order = _orderJson(id, uid, body, quote);
      orders[id] = order;
      ordersByKey[key] = order;
      if (dropNextCreateResponse) {
        dropNextCreateResponse = false;
        throw http.ClientException('Mất kết nối giữa chừng');
      }
      return jsonResponse(order, 201);
    }

    if (path == '/api/orders/me') {
      final status = request.url.queryParameters['status'];
      final group = switch (status) {
        'active' => const {'received', 'cooking', 'ready'},
        'completed' => const {'completed'},
        'cancelled' => const {'cancelled'},
        _ => null,
      };
      final list = orders.values.where((o) => group == null || group.contains(o['status'])).map(_summary).toList()
        ..sort((a, b) => (b['createdAt'] as String).compareTo(a['createdAt'] as String));
      final page = int.tryParse(request.url.queryParameters['page'] ?? '') ?? 1;
      final size = int.tryParse(request.url.queryParameters['pageSize'] ?? '') ?? 20;
      return jsonResponse({
        'items': list.skip((page - 1) * size).take(size).toList(),
        'page': page,
        'pageSize': size,
        'totalCount': list.length,
        'totalPages': (list.length / size).ceil(),
        'hasNext': page * size < list.length,
      }, 200);
    }

    if (path == '/api/notifications/read-all') {
      readAllCalls++;
      return jsonResponse({'updated': 1}, 200);
    }
    final readMatch = RegExp(r'^/api/notifications/(\d+)/read$').firstMatch(path);
    if (readMatch != null) {
      readNotificationIds.add(int.parse(readMatch.group(1)!));
      return http.Response('', 204);
    }

    final cancel = RegExp(r'^/api/orders/([^/]+)/cancel$').firstMatch(path);
    if (cancel != null) {
      final order = orders[cancel.group(1)];
      if (order == null) return problem(404, 'NOT_FOUND', 'Không tìm thấy đơn.');
      if (order['status'] != 'received') {
        return problem(422, 'ORDER_NOT_CANCELLABLE', 'Căn-tin đã bắt đầu nấu — không thể hủy đơn.');
      }
      final reason = (jsonDecode(request.body) as Map<String, dynamic>)['reason'];
      setStatus(order['id']! as String, 'cancelled', cancelReason: reason as String?);
      return jsonResponse(order, 200);
    }

    final match = RegExp(r'^/api/orders/([^/]+)(/payment/sync)?$').firstMatch(path);
    if (match != null && match.group(1) != 'me') {
      final order = orders[match.group(1)];
      if (order == null) return problem(404, 'NOT_FOUND', 'Không tìm thấy đơn.');
      if (paidOrderIds.contains(order['id'])) {
        order['paymentStatus'] = 'paid';
        (order['payment']! as Map<String, Object?>)
          ..['status'] = 'paid'
          ..['qrCode'] = null;
      }
      return jsonResponse(order, 200);
    }
    return null;
  }
}
