import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import 'api_exception.dart';

/// Lấy Firebase ID token hiện tại (null nếu chưa đăng nhập).
typedef TokenProvider = Future<String?> Function();

/// Client gọi REST API của backend.
///
///  - Tự gắn `Authorization: Bearer <Firebase ID token>`; token được lấy mới trước mỗi request
///    (Firebase tự làm mới khi sắp hết hạn 1 giờ).
///  - Giải mã JSON bằng `jsonDecode` (UTF-8, tiếng Việt).
///  - Lỗi HTTP → [ApiException] đọc từ ProblemDetails; mất mạng/timeout → [ApiException] có thông báo dễ hiểu.
///  - Các lỗi cần xử lý chung (401, tài khoản bị khóa, chưa có hồ sơ) được phát qua [authErrors]
///    để AuthProvider điều hướng — từng màn không phải tự xử lý.
class ApiClient {
  ApiClient({
    required this._baseUrl,
    this._tokenProvider,
    http.Client? httpClient,
    this._timeout = AppConfig.requestTimeout,
  }) : _http = httpClient ?? http.Client();

  final String Function() _baseUrl;
  final TokenProvider? _tokenProvider;
  final http.Client _http;
  final Duration _timeout;

  final StreamController<ApiException> _authErrors = StreamController<ApiException>.broadcast();

  /// 401 / ACCOUNT_LOCKED / PROFILE_NOT_FOUND từ bất kỳ request nào.
  Stream<ApiException> get authErrors => _authErrors.stream;

  String get baseUrl => _baseUrl();

  // ============================ HTTP methods ============================

  Future<dynamic> get(String path, {Map<String, Object?>? query}) => _send('GET', path, query: query);

  Future<dynamic> post(String path, {Object? body, Map<String, String>? headers}) =>
      _send('POST', path, body: body, headers: headers);

  Future<dynamic> put(String path, {Object? body}) => _send('PUT', path, body: body);

  Future<dynamic> patch(String path, {Object? body}) => _send('PATCH', path, body: body);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  /// Upload một file ảnh (multipart/form-data, field "file").
  Future<dynamic> upload(String path, {required List<int> bytes, required String fileName}) async {
    final request = http.MultipartRequest('POST', _uri(path))
      ..headers.addAll(await _headers(json: false))
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
    return _execute(() async => http.Response.fromStream(await _http.send(request).timeout(_timeout)));
  }

  /// Kiểm tra kết nối tới một địa chỉ máy chủ (màn Cài đặt máy chủ) — không cần đăng nhập.
  Future<bool> checkHealth({String? baseUrl}) async {
    final url = '${AppConfig.normalizeBaseUrl(baseUrl ?? _baseUrl())}/api/health';
    try {
      final response = await _http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _authErrors.close();
    _http.close();
  }

  // ============================ Nội bộ ============================

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, Object?>? query,
    Object? body,
    Map<String, String>? headers,
  }) async {
    final request = http.Request(method, _uri(path, query))
      ..headers.addAll(await _headers(json: body != null))
      ..headers.addAll(headers ?? const {});
    if (body != null) request.body = jsonEncode(body);

    return _execute(() async => http.Response.fromStream(await _http.send(request).timeout(_timeout)));
  }

  Future<dynamic> _execute(Future<http.Response> Function() call) async {
    final http.Response response;
    try {
      response = await call();
    } on TimeoutException {
      throw ApiException.timeout();
    } on SocketException {
      throw ApiException.network();
    } on http.ClientException {
      throw ApiException.network();
    } on HandshakeException {
      throw ApiException.network('Không thiết lập được kết nối bảo mật tới máy chủ.');
    }

    final text = utf8.decode(response.bodyBytes);
    final decoded = text.isEmpty ? null : _tryDecode(text);

    if (response.statusCode >= 200 && response.statusCode < 300) return decoded;

    final error = ApiException.fromResponse(response.statusCode, decoded);
    if (error.isUnauthorized ||
        error.code == ApiErrorCodes.accountLocked ||
        (error.code == ApiErrorCodes.profileNotFound && error.statusCode == 403)) {
      _authErrors.add(error);
    }
    throw error;
  }

  Uri _uri(String path, [Map<String, Object?>? query]) {
    final params = <String, dynamic>{};
    query?.forEach((key, value) {
      if (value == null) return;
      params[key] = value is Iterable ? value.map((v) => '$v').toList() : '$value';
    });
    return Uri.parse('${AppConfig.normalizeBaseUrl(_baseUrl())}$path')
        .replace(queryParameters: params.isEmpty ? null : params);
  }

  Future<Map<String, String>> _headers({required bool json}) async {
    final token = await _tokenProvider?.call();
    return {
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json; charset=utf-8',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Object? _tryDecode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }
}
