/// Cấu hình kết nối backend.
///
/// Địa chỉ mặc định:
///  - truyền khi build: `flutter run --dart-define=API_BASE_URL=http://192.168.1.10:5265`
///  - nếu không truyền: `http://10.0.2.2:5265` — địa chỉ của máy tính khi nhìn từ Android Emulator.
/// Người dùng có thể đổi trong màn "Cài đặt máy chủ" (lưu lại, không cần build lại APK) —
/// dùng khi cài APK lên điện thoại thật và gọi backend qua IP laptop trong cùng mạng Wi-Fi.
abstract final class AppConfig {
  static const String defaultApiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:5265');

  /// Thời gian chờ tối đa cho một request REST.
  static const Duration requestTimeout = Duration(seconds: 20);

  /// Chuẩn hóa địa chỉ người dùng nhập: bỏ khoảng trắng và dấu "/" cuối.
  static String normalizeBaseUrl(String url) {
    var value = url.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}
