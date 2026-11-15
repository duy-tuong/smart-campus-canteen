namespace CanteenApi.Common;

/// <summary>
/// Mã lỗi ổn định trả về trong trường "code" của ProblemDetails.
/// App Flutter dựa vào mã này (không dựa vào câu chữ) để quyết định cách xử lý/hiển thị.
/// </summary>
public static class ErrorCodes
{
    // Chung
    public const string ValidationError = "VALIDATION_ERROR";
    public const string NotFound = "NOT_FOUND";
    public const string Duplicate = "DUPLICATE";
    public const string ConstraintViolation = "CONSTRAINT_VIOLATION";
    public const string ConcurrencyConflict = "CONCURRENCY_CONFLICT";
    public const string InternalError = "INTERNAL_ERROR";

    // Xác thực & phân quyền
    public const string Unauthorized = "UNAUTHORIZED";
    public const string Forbidden = "FORBIDDEN";
    public const string AccountLocked = "ACCOUNT_LOCKED";
    public const string ProfileNotFound = "PROFILE_NOT_FOUND";
    public const string CannotModifySelf = "CANNOT_MODIFY_SELF";

    // Người dùng
    public const string StudentCodeTaken = "STUDENT_CODE_TAKEN";
    public const string StudentCodeLocked = "STUDENT_CODE_LOCKED";

    // Thực đơn
    public const string CategoryNameTaken = "CATEGORY_NAME_TAKEN";
    public const string CategoryNotEmpty = "CATEGORY_NOT_EMPTY";
    public const string FoodNameTaken = "FOOD_NAME_TAKEN";
    public const string InvalidOptions = "INVALID_OPTIONS";

    // File
    public const string InvalidFile = "INVALID_FILE";
}
