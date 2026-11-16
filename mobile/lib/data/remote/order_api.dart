import '../../models/cart_item.dart';
import '../../models/checkout.dart';
import '../../models/enums.dart';
import '../../models/order.dart';
import 'api_client.dart';

/// REST: báo giá, đặt món, thanh toán, voucher, thông tin căn-tin.
class OrderApi {
  OrderApi(this._api);

  final ApiClient _api;

  Future<CanteenInfo> canteenInfo() async =>
      CanteenInfo.fromJson(await _api.get('/api/canteen/info') as Map<String, dynamic>);

  /// Báo giá giỏ hàng — KHÔNG tạo đơn. Lỗi theo từng dòng nằm trong [Quote.errors] (không ném).
  Future<Quote> quote(List<CartItem> items, {String? voucherCode}) async => Quote.fromJson(
    await _api.post(
          '/api/orders/quote',
          body: {'items': items.map(cartLineJson).toList(), 'voucherCode': _blankToNull(voucherCode)},
        )
        as Map<String, dynamic>,
  );

  Future<List<AvailableVoucher>> availableVouchers() async => (await _api.get('/api/vouchers/available') as List)
      .whereType<Map<String, dynamic>>()
      .map(AvailableVoucher.fromJson)
      .toList();

  /// Đặt món. [idempotencyKey]: GUID cho MỘT lần bấm "Đặt món" — gửi lại cùng key (mạng chập chờn)
  /// thì máy chủ trả lại đơn đã tạo thay vì tạo đơn trùng.
  Future<OrderDetail> createOrder({
    required List<CartItem> items,
    required PaymentMethod paymentMethod,
    required String idempotencyKey,
    String? voucherCode,
    DateTime? pickupTime,
    String? note,
  }) async => OrderDetail.fromJson(
    await _api.post(
          '/api/orders',
          headers: {'Idempotency-Key': idempotencyKey},
          body: {
            'items': items.map(cartLineJson).toList(),
            'voucherCode': _blankToNull(voucherCode),
            'paymentMethod': paymentMethod.name,
            'pickupTime': pickupTime?.toUtc().toIso8601String(),
            'note': _blankToNull(note),
          },
        )
        as Map<String, dynamic>,
  );

  Future<OrderDetail> getOrder(String id) async =>
      OrderDetail.fromJson(await _api.get('/api/orders/$id') as Map<String, dynamic>);

  /// "Tôi đã chuyển khoản": máy chủ hỏi payOS ngay, trả về đơn sau khi đồng bộ.
  Future<OrderDetail> syncPayment(String id) async =>
      OrderDetail.fromJson(await _api.post('/api/orders/$id/payment/sync') as Map<String, dynamic>);

  static String? _blankToNull(String? value) => (value == null || value.trim().isEmpty) ? null : value.trim();
}
