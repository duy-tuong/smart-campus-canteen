import 'dart:convert';
import 'dart:typed_data';

import 'package:campus_canteen/data/device/image_source_service.dart';
import 'package:http/http.dart' as http;

import 'fakes.dart';

/// Chọn ảnh giả (không cần camera): trả về ảnh PNG nhỏ, hoặc null nếu [cancel].
class FakeImageSource implements ImageSourceService {
  bool cancel = false;
  final List<PickSource> requests = [];

  @override
  Future<PickedImage?> pick(PickSource source) async {
    requests.add(source);
    if (cancel) return null;
    return PickedImage(bytes: Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47]), fileName: 'avatar.png');
  }
}

/// Phần "hồ sơ & đánh giá" của backend giả.
mixin FakeReviewing {
  Map<String, Map<String, Object?>> get profiles;
  Map<String, Map<String, Object?>> get orders;

  /// Đánh giá theo id; mặc định hạn đánh giá còn.
  Map<int, Map<String, Object?>> get reviews => _reviews;
  final Map<int, Map<String, Object?>> _reviews = {};
  bool reviewWindowOpen = true;
  int _nextReviewId = 100;

  Map<String, Object?> addReview({
    required String orderId,
    required int foodId,
    required String foodName,
    int rating = 4,
    String? comment,
    bool hidden = false,
    String? hiddenReason,
    String? staffReply,
    bool canEdit = true,
  }) {
    final id = _nextReviewId++;
    return reviews[id] = {
      'id': id,
      'foodId': foodId,
      'foodName': foodName,
      'orderId': orderId,
      'rating': rating,
      'comment': comment,
      'authorName': 'An N.',
      'isMine': true,
      'canEdit': canEdit && !hidden,
      'isHidden': hidden,
      'hiddenReason': hiddenReason,
      'staffReply': staffReply,
      'repliedAt': null,
      'createdAt': '2026-11-16T04:00:00Z',
      'updatedAt': '2026-11-16T04:00:00Z',
    };
  }

  http.Response? handleReviewing(http.Request request, String uid) {
    final path = request.url.path;
    final method = request.method;

    // ----- Hồ sơ -----
    if (path == '/api/users/me' && method == 'PUT') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final profile = profiles[uid]!;
      final code = body['studentCode'];
      if (code != null && profile['studentCode'] != null && code != profile['studentCode']) {
        return problem(422, 'STUDENT_CODE_LOCKED', 'Không được đổi mã số sinh viên đã có.');
      }
      profile
        ..['fullName'] = body['fullName']
        ..['phone'] = body['phone'];
      if (code != null) profile['studentCode'] = code;
      return jsonResponse(profile, 200);
    }
    if (path == '/api/users/me/avatar') {
      final profile = profiles[uid]!;
      if (method == 'DELETE') {
        profile['avatarUrl'] = null;
        return http.Response('', 204);
      }
      profile['avatarUrl'] = 'http://api.test/uploads/avatars/$uid.png';
      return jsonResponse(profile, 200);
    }

    // ----- Đánh giá -----
    if (path == '/api/users/me/reviews') {
      final list = reviews.values.toList()..sort((a, b) => (b['id']! as int).compareTo(a['id']! as int));
      return jsonResponse({
        'items': list,
        'page': 1,
        'pageSize': 20,
        'totalCount': list.length,
        'totalPages': 1,
        'hasNext': false,
      }, 200);
    }

    final orderReviews = RegExp(r'^/api/orders/([^/]+)/reviews$').firstMatch(path);
    if (orderReviews != null) {
      final orderId = orderReviews.group(1)!;
      final order = orders[orderId];
      if (order == null) return problem(404, 'NOT_FOUND', 'Không tìm thấy đơn hàng.');
      final completed = order['status'] == 'completed';
      if (method == 'GET') {
        return jsonResponse({
          'orderId': orderId,
          'canReview': completed && reviewWindowOpen,
          'reviewDeadline': '2026-11-23T03:00:00Z',
          'items': [
            for (final i in (order['items']! as List).cast<Map<String, Object?>>())
              {
                'foodId': i['foodId'],
                'foodName': i['foodName'],
                'imageUrl': null,
                'quantity': i['quantity'],
                'myReview': reviews.values
                    .where((r) => r['orderId'] == orderId && r['foodId'] == i['foodId'])
                    .firstOrNull,
              },
          ],
        }, 200);
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (!completed) return problem(422, 'REVIEW_NOT_ALLOWED', 'Chỉ đánh giá được sau khi đã nhận món.');
      if (!reviewWindowOpen) return problem(422, 'REVIEW_WINDOW_CLOSED', 'Đã quá hạn đánh giá.');
      if (reviews.values.any((r) => r['orderId'] == orderId && r['foodId'] == body['foodId'])) {
        return problem(409, 'REVIEW_EXISTS', 'Bạn đã đánh giá món này trong đơn rồi. Hãy sửa đánh giá cũ.');
      }
      final item = (order['items']! as List).cast<Map<String, Object?>>().firstWhere(
        (i) => i['foodId'] == body['foodId'],
      );
      final review = addReview(
        orderId: orderId,
        foodId: body['foodId'] as int,
        foodName: item['foodName']! as String,
        rating: body['rating'] as int,
        comment: body['comment'] as String?,
      );
      return jsonResponse(review, 201);
    }

    final one = RegExp(r'^/api/reviews/(\d+)$').firstMatch(path);
    if (one != null) {
      final id = int.parse(one.group(1)!);
      final review = reviews[id];
      if (review == null) return problem(404, 'NOT_FOUND', 'Không tìm thấy đánh giá.');
      if (method == 'DELETE') {
        reviews.remove(id);
        return http.Response('', 204);
      }
      if (review['isHidden'] == true) return problem(422, 'REVIEW_HIDDEN', 'Đánh giá đã bị ẩn nên không thể sửa.');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      review
        ..['rating'] = body['rating']
        ..['comment'] = body['comment'];
      return jsonResponse(review, 200);
    }
    return null;
  }
}
