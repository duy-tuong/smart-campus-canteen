/// Các enum khớp với backend (JSON dạng chuỗi camelCase: "received", "bankTransfer"...).
library;

enum UserRole {
  student('Sinh viên'),
  staff('Nhân viên căn-tin'),
  admin('Quản trị viên');

  const UserRole(this.label);
  final String label;

  bool get isStaffOrAdmin => this == staff || this == admin;

  static UserRole fromJson(Object? value) => _byName(values, value, student);
}

/// Trạng thái chế biến của đơn: received → cooking → ready → completed (hoặc cancelled).
enum OrderStatus {
  received('Đã nhận', 'Căn-tin đã nhận đơn của bạn'),
  cooking('Đang nấu', 'Món của bạn đang được chế biến'),
  ready('Mời nhận món', 'Món đã xong — mời bạn đến quầy'),
  completed('Hoàn thành', 'Bạn đã nhận món. Chúc ngon miệng!'),
  cancelled('Đã hủy', 'Đơn hàng đã bị hủy');

  const OrderStatus(this.label, this.description);
  final String label;

  /// Câu mô tả tự tin, hướng tới người dùng (hiển thị trên màn Theo dõi đơn).
  final String description;

  bool get isActive => this == received || this == cooking || this == ready;

  /// Thứ tự trên dòng thời gian (hủy không nằm trên dòng thời gian).
  int get step => switch (this) {
    received => 0,
    cooking => 1,
    ready => 2,
    completed => 3,
    cancelled => -1,
  };

  static OrderStatus fromJson(Object? value) => _byName(values, value, received);
}

enum PaymentMethod {
  cash('Tiền mặt tại quầy'),
  bankTransfer('Chuyển khoản (QR)');

  const PaymentMethod(this.label);
  final String label;

  static PaymentMethod fromJson(Object? value) => _byName(values, value, cash);
}

enum PaymentStatus {
  pending('Chờ thanh toán'),
  paid('Đã thanh toán'),
  refunded('Hoàn tiền'),
  failed('Không thành công');

  const PaymentStatus(this.label);
  final String label;

  static PaymentStatus fromJson(Object? value) => _byName(values, value, pending);
}

/// Tìm enum theo tên (không phân biệt hoa thường); giá trị lạ → [fallback] để app không crash
/// khi backend thêm trạng thái mới.
T _byName<T extends Enum>(List<T> values, Object? value, T fallback) {
  final name = '$value'.toLowerCase();
  for (final v in values) {
    if (v.name.toLowerCase() == name) return v;
  }
  return fallback;
}
