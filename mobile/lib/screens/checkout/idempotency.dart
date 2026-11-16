import 'package:uuid/uuid.dart';

/// Giữ Idempotency-Key cho lần đặt món đang dở.
///
/// - Bấm "Đặt món" lần đầu → sinh GUID mới.
/// - Mất mạng / hết thời gian chờ → bấm lại với CÙNG nội dung đơn → dùng LẠI key cũ:
///   nếu lần trước máy chủ đã tạo đơn, máy chủ trả lại đúng đơn đó (không tạo đơn trùng).
/// - Đổi nội dung đơn (món, voucher, phương thức, giờ hẹn, ghi chú) → key mới (đơn khác).
class IdempotencyKeeper {
  IdempotencyKeeper({String Function()? generate}) : _generate = generate ?? const Uuid().v4;

  final String Function() _generate;
  String? _key;
  String? _signature;

  /// Key cho đơn có "chữ ký" [signature] (chuỗi mô tả toàn bộ nội dung đơn).
  String keyFor(String signature) {
    if (_key == null || _signature != signature) {
      _key = _generate();
      _signature = signature;
    }
    return _key!;
  }

  /// Đặt món xong (thành công hoặc bị từ chối rõ ràng) → lần sau dùng key mới.
  void reset() {
    _key = null;
    _signature = null;
  }
}
