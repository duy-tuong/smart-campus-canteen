/// Lỗi khi gọi REST API — đọc từ ProblemDetails của backend:
/// `{ status, title, detail, code, traceId, errors?, items?, allowedStatuses? }`.
///
/// App quyết định cách xử lý theo [code] (ổn định), KHÔNG theo câu chữ [message].
class ApiException implements Exception {
  ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.fieldErrors = const {},
    this.extras = const {},
    this.traceId,
  });

  /// Không kết nối được máy chủ (sai địa chỉ, backend chưa chạy, mất mạng).
  factory ApiException.network([String? detail]) => ApiException(
    statusCode: 0,
    code: networkError,
    message: detail ?? 'Không kết nối được máy chủ. Kiểm tra mạng hoặc địa chỉ máy chủ trong Cài đặt.',
  );

  factory ApiException.timeout() =>
      ApiException(statusCode: 0, code: timeoutError, message: 'Máy chủ phản hồi quá lâu. Vui lòng thử lại.');

  /// Đọc body lỗi (đã jsonDecode). Body không đúng chuẩn vẫn trả về lỗi có nghĩa.
  factory ApiException.fromResponse(int statusCode, Object? body) {
    final json = body is Map<String, dynamic> ? body : const <String, dynamic>{};

    final fieldErrors = <String, List<String>>{};
    final errors = json['errors'];
    if (errors is Map<String, dynamic>) {
      errors.forEach((field, messages) {
        if (messages is List) fieldErrors[field] = messages.map((m) => '$m').toList();
      });
    }

    final extras = Map<String, dynamic>.from(json)
      ..removeWhere(
        (key, _) => const {'type', 'title', 'status', 'detail', 'code', 'traceId', 'errors', 'instance'}.contains(key),
      );

    return ApiException(
      statusCode: statusCode,
      code: json['code'] as String? ?? _codeFromStatus(statusCode),
      message: json['detail'] as String? ?? json['title'] as String? ?? _messageFromStatus(statusCode),
      fieldErrors: fieldErrors,
      extras: extras,
      traceId: json['traceId'] as String?,
    );
  }

  static const networkError = 'NETWORK_ERROR';
  static const timeoutError = 'TIMEOUT';

  final int statusCode;
  final String code;
  final String message;

  /// Lỗi theo từng trường của form: { "FullName": ["Họ tên dài từ 2 đến 100 ký tự."] }.
  final Map<String, List<String>> fieldErrors;

  /// Trường mở rộng: "items" (lỗi theo từng món trong giỏ), "allowedStatuses"...
  final Map<String, dynamic> extras;

  final String? traceId;

  bool get isNetwork => code == networkError || code == timeoutError;
  bool get isUnauthorized => statusCode == 401;
  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;

  /// Lỗi đầu tiên của một trường (dùng làm errorText cho ô nhập), không phân biệt hoa thường.
  String? fieldError(String field) {
    for (final entry in fieldErrors.entries) {
      if (entry.key.toLowerCase() == field.toLowerCase() && entry.value.isNotEmpty) return entry.value.first;
    }
    return null;
  }

  /// Danh sách lỗi theo từng dòng giỏ hàng (ORDER_ITEMS_INVALID): [{ index, foodId, code, message, remaining }].
  List<Map<String, dynamic>> get lineErrors =>
      (extras['items'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? const [];

  @override
  String toString() => 'ApiException($statusCode $code: $message)';

  static String _codeFromStatus(int status) => switch (status) {
    400 => 'VALIDATION_ERROR',
    401 => 'UNAUTHORIZED',
    403 => 'FORBIDDEN',
    404 => 'NOT_FOUND',
    409 => 'CONFLICT',
    _ => 'HTTP_$status',
  };

  static String _messageFromStatus(int status) => switch (status) {
    401 => 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
    403 => 'Bạn không có quyền thực hiện thao tác này.',
    404 => 'Không tìm thấy dữ liệu.',
    >= 500 => 'Máy chủ đang gặp sự cố. Vui lòng thử lại sau.',
    _ => 'Đã có lỗi xảy ra (mã $status).',
  };
}

/// Mã lỗi backend mà toàn app cần xử lý chung.
abstract final class ApiErrorCodes {
  static const unauthorized = 'UNAUTHORIZED';
  static const accountLocked = 'ACCOUNT_LOCKED';
  static const profileNotFound = 'PROFILE_NOT_FOUND';
  static const concurrencyConflict = 'CONCURRENCY_CONFLICT';
  static const validationError = 'VALIDATION_ERROR';
  static const orderItemsInvalid = 'ORDER_ITEMS_INVALID';
  static const studentCodeTaken = 'STUDENT_CODE_TAKEN';
  static const studentCodeLocked = 'STUDENT_CODE_LOCKED';
}
