import '../../models/enums.dart';
import '../../models/menu.dart';
import '../../models/order.dart';
import '../../models/paged_result.dart';
import '../../models/review.dart';
import '../../models/voucher.dart';
import 'api_client.dart';

/// REST dành cho nhân viên căn-tin / quản trị: xử lý đơn, quản lý thực đơn, voucher, đánh giá.
class StaffApi {
  StaffApi(this._api);

  final ApiClient _api;

  // ------------------------------ Đơn hàng ------------------------------

  /// Chuyển bước: received → cooking → ready → completed. 422 PAYMENT_REQUIRED nếu đơn chuyển khoản chưa trả;
  /// 409 nếu nhân viên khác vừa cập nhật.
  Future<OrderDetail> changeStatus(String id, OrderStatus status, {String? note}) async => OrderDetail.fromJson(
    await _api.patch('/api/orders/$id/status', body: {'status': status.name, 'note': note}) as Map<String, dynamic>,
  );

  /// Xác nhận đã nhận tiền chuyển khoản (khách đưa ảnh chụp giao dịch tại quầy).
  Future<OrderDetail> confirmPayment(String id) async =>
      OrderDetail.fromJson(await _api.post('/api/orders/$id/payment/confirm') as Map<String, dynamic>);

  Future<OrderDetail> cancelOrder(String id, String reason) async => OrderDetail.fromJson(
    await _api.post('/api/orders/$id/cancel', body: {'reason': reason.trim()}) as Map<String, dynamic>,
  );

  Future<OrderDetail> order(String id) async =>
      OrderDetail.fromJson(await _api.get('/api/orders/$id') as Map<String, dynamic>);

  // ------------------------------ Danh mục ------------------------------

  Future<List<Category>> categories() async =>
      (await _api.get('/api/categories', query: {'includeInactive': true}) as List)
          .whereType<Map<String, dynamic>>()
          .map(Category.fromJson)
          .toList();

  Future<Category> saveCategory({
    int? id,
    required String name,
    String? description,
    required String icon,
    required int sortOrder,
    required bool isActive,
  }) async {
    final body = {
      'name': name.trim(),
      'description': (description == null || description.trim().isEmpty) ? null : description.trim(),
      'icon': icon,
      'sortOrder': sortOrder,
      'isActive': isActive,
    };
    final json = id == null
        ? await _api.post('/api/categories', body: body)
        : await _api.put('/api/categories/$id', body: body);
    return Category.fromJson(json as Map<String, dynamic>);
  }

  /// Sắp xếp lại (kéo-thả): gửi thứ tự mới của mọi danh mục một lần.
  Future<List<Category>> reorderCategories(List<int> idsInOrder) async =>
      (await _api.put(
                '/api/categories/order',
                body: {
                  'items': [
                    for (final (i, id) in idsInOrder.indexed) {'id': id, 'sortOrder': i + 1},
                  ],
                },
              )
              as List)
          .whereType<Map<String, dynamic>>()
          .map(Category.fromJson)
          .toList();

  /// 409 CATEGORY_NOT_EMPTY nếu danh mục còn món.
  Future<void> deleteCategory(int id) => _api.delete('/api/categories/$id');

  // ------------------------------ Món ăn ------------------------------

  /// Mọi món (kể cả đang ẩn / ngừng bán) để quản lý.
  Future<PagedResult<FoodSummary>> foods({int? categoryId, String? q, int page = 1, int pageSize = 50}) async =>
      PagedResult.fromJson(
        await _api.get(
              '/api/foods',
              query: {
                'includeInactive': true,
                'categoryId': categoryId,
                'q': (q == null || q.trim().isEmpty) ? null : q.trim(),
                'sort': 'name',
                'page': page,
                'pageSize': pageSize,
              },
            )
            as Map<String, dynamic>,
        FoodSummary.fromJson,
      );

  Future<FoodDetail> food(int id) async =>
      FoodDetail.fromJson(await _api.get('/api/foods/$id') as Map<String, dynamic>);

  Future<FoodDetail> createFood(FoodDraft draft, List<OptionGroupDraft> groups) async => FoodDetail.fromJson(
    await _api.post(
          '/api/foods',
          body: {
            ...draft.toJson(),
            'optionGroups': [for (final (i, g) in groups.indexed) g.toJson(i + 1)],
          },
        )
        as Map<String, dynamic>,
  );

  /// 409 CONCURRENCY_CONFLICT nếu [rowVersion] cũ (người khác vừa sửa).
  Future<FoodDetail> updateFood(int id, FoodDraft draft, String rowVersion) async => FoodDetail.fromJson(
    await _api.put('/api/foods/$id', body: {...draft.toJson(), 'rowVersion': rowVersion}) as Map<String, dynamic>,
  );

  Future<FoodDetail> replaceOptionGroups(int id, List<OptionGroupDraft> groups) async => FoodDetail.fromJson(
    await _api.put(
          '/api/foods/$id/option-groups',
          body: {
            'groups': [for (final (i, g) in groups.indexed) g.toJson(i + 1)],
          },
        )
        as Map<String, dynamic>,
  );

  Future<FoodDetail> setAvailability(int id, bool isAvailable) async => FoodDetail.fromJson(
    await _api.patch('/api/foods/$id/availability', body: {'isAvailable': isAvailable}) as Map<String, dynamic>,
  );

  Future<FoodDetail> uploadFoodImage(int id, List<int> bytes, String fileName) async => FoodDetail.fromJson(
    await _api.upload('/api/foods/$id/image', bytes: bytes, fileName: fileName) as Map<String, dynamic>,
  );

  Future<void> deleteFood(int id) => _api.delete('/api/foods/$id');

  // ------------------------------ Voucher ------------------------------

  Future<PagedResult<AdminVoucher>> vouchers({String? q, bool? isActive, int page = 1}) async => PagedResult.fromJson(
    await _api.get(
          '/api/admin/vouchers',
          query: {
            'q': (q == null || q.trim().isEmpty) ? null : q.trim(),
            'isActive': isActive,
            'page': page,
            'pageSize': 50,
          },
        )
        as Map<String, dynamic>,
    AdminVoucher.fromJson,
  );

  Future<AdminVoucher> saveVoucher(Map<String, Object?> body, {int? id}) async {
    final json = id == null
        ? await _api.post('/api/admin/vouchers', body: body)
        : await _api.put('/api/admin/vouchers/$id', body: body);
    return AdminVoucher.fromJson(json as Map<String, dynamic>);
  }

  Future<AdminVoucher> setVoucherActive(int id, bool isActive) async => AdminVoucher.fromJson(
    await _api.patch('/api/admin/vouchers/$id/status', body: {'isActive': isActive}) as Map<String, dynamic>,
  );

  /// 409 VOUCHER_IN_USE nếu đã có đơn dùng mã.
  Future<void> deleteVoucher(int id) => _api.delete('/api/admin/vouchers/$id');

  // ------------------------------ Đánh giá ------------------------------

  Future<PagedResult<Review>> reviews({bool? hasReply, bool? isHidden, int? rating, int page = 1}) async =>
      PagedResult.fromJson(
        await _api.get(
              '/api/admin/reviews',
              query: {'hasReply': hasReply, 'isHidden': isHidden, 'rating': rating, 'page': page, 'pageSize': 20},
            )
            as Map<String, dynamic>,
        Review.fromJson,
      );

  Future<Review> setReviewHidden(int id, bool hidden, {String? reason}) async => Review.fromJson(
    await _api.patch('/api/admin/reviews/$id/visibility', body: {'isHidden': hidden, 'reason': reason})
        as Map<String, dynamic>,
  );

  Future<Review> replyReview(int id, String reply) async => Review.fromJson(
    await _api.put('/api/admin/reviews/$id/reply', body: {'reply': reply.trim()}) as Map<String, dynamic>,
  );

  Future<Review> removeReply(int id) async =>
      Review.fromJson(await _api.delete('/api/admin/reviews/$id/reply') as Map<String, dynamic>);
}
