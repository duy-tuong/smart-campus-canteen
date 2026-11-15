namespace CanteenApi.Common;

/// <summary>
/// Lỗi nghiệp vụ có chủ đích. Service ném exception này; GlobalExceptionHandler
/// chuyển thành response ProblemDetails với đúng HTTP status và mã lỗi.
/// </summary>
public class AppException(int statusCode, string code, string message) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
    public string Code { get; } = code;
}

/// <summary>400 — dữ liệu gửi lên không hợp lệ (ngoài validate DTO tự động).</summary>
public sealed class BadRequestException(string code, string message)
    : AppException(StatusCodes.Status400BadRequest, code, message);

/// <summary>403 — đã đăng nhập nhưng không được phép thực hiện thao tác.</summary>
public sealed class ForbiddenException(string code, string message)
    : AppException(StatusCodes.Status403Forbidden, code, message);

/// <summary>404 — không tìm thấy tài nguyên.</summary>
public sealed class NotFoundException(string message, string code = ErrorCodes.NotFound)
    : AppException(StatusCodes.Status404NotFound, code, message);

/// <summary>409 — xung đột trạng thái dữ liệu (trùng, đang được sử dụng, bị sửa đồng thời).</summary>
public sealed class ConflictException(string code, string message)
    : AppException(StatusCodes.Status409Conflict, code, message);

/// <summary>422 — dữ liệu đúng định dạng nhưng vi phạm quy tắc nghiệp vụ.</summary>
public sealed class BusinessRuleException(string code, string message)
    : AppException(StatusCodes.Status422UnprocessableEntity, code, message);
