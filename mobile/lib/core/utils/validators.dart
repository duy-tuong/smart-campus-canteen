/// Kiểm tra dữ liệu form — dùng chung cho TextFormField.validator.
/// Quy tắc khớp với backend (UserRules trong CanteenApi) để báo lỗi ngay trên app, trước khi gửi.
abstract final class Validators {
  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final RegExp _studentCode = RegExp(r'^\d{10}$');
  static final RegExp _phone = RegExp(r'^(0|\+84)\d{9}$');
  static final RegExp _url = RegExp(r'^https?://[^\s/$.?#].[^\s]*$', caseSensitive: false);

  static String? required(String? value, [String message = 'Vui lòng nhập thông tin.']) =>
      (value == null || value.trim().isEmpty) ? message : null;

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return 'Vui lòng nhập email.';
    return _email.hasMatch(value.trim()) ? null : 'Email không đúng định dạng.';
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Vui lòng nhập mật khẩu.';
    return value.length < 6 ? 'Mật khẩu tối thiểu 6 ký tự.' : null;
  }

  static String? fullName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Vui lòng nhập họ tên.';
    return v.length < 2 || v.length > 100 ? 'Họ tên dài từ 2 đến 100 ký tự.' : null;
  }

  static String? studentCode(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Vui lòng nhập mã số sinh viên.';
    return _studentCode.hasMatch(v) ? null : 'Mã số sinh viên gồm đúng 10 chữ số.';
  }

  /// Số điện thoại không bắt buộc; nếu nhập thì phải đúng định dạng.
  static String? optionalPhone(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    return _phone.hasMatch(v) ? null : 'Số điện thoại dạng 0xxxxxxxxx hoặc +84xxxxxxxxx.';
  }

  static String? serverUrl(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Vui lòng nhập địa chỉ máy chủ.';
    return _url.hasMatch(v) ? null : 'Địa chỉ dạng http://192.168.1.10:5265';
  }
}
