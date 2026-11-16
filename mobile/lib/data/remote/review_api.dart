import '../../models/paged_result.dart';
import '../../models/review.dart';
import 'api_client.dart';

/// REST: đánh giá món của tôi (viết / sửa / xóa trong hạn 7 ngày sau khi nhận món).
class ReviewApi {
  ReviewApi(this._api);

  final ApiClient _api;

  Future<OrderReviews> forOrder(String orderId) async =>
      OrderReviews.fromJson(await _api.get('/api/orders/$orderId/reviews') as Map<String, dynamic>);

  /// 409 REVIEW_EXISTS nếu món này trong đơn đã có đánh giá; 422 REVIEW_WINDOW_CLOSED nếu quá hạn.
  Future<Review> create(String orderId, {required int foodId, required int rating, String? comment}) async =>
      Review.fromJson(
        await _api.post(
              '/api/orders/$orderId/reviews',
              body: {'foodId': foodId, 'rating': rating, 'comment': _blankToNull(comment)},
            )
            as Map<String, dynamic>,
      );

  /// 422 REVIEW_HIDDEN nếu đánh giá đã bị căn-tin ẩn.
  Future<Review> update(int id, {required int rating, String? comment}) async => Review.fromJson(
    await _api.put('/api/reviews/$id', body: {'rating': rating, 'comment': _blankToNull(comment)})
        as Map<String, dynamic>,
  );

  Future<void> delete(int id) => _api.delete('/api/reviews/$id');

  /// Đánh giá của tôi (kể cả bị ẩn — kèm lý do), mới nhất trước.
  Future<PagedResult<Review>> mine({int page = 1, int pageSize = 20}) async => PagedResult.fromJson(
    await _api.get('/api/users/me/reviews', query: {'page': page, 'pageSize': pageSize}) as Map<String, dynamic>,
    Review.fromJson,
  );

  static String? _blankToNull(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
}
