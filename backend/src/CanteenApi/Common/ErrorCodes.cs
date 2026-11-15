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
    public const string InvalidCategory = "INVALID_CATEGORY";
    public const string CategoryNotEmpty = "CATEGORY_NOT_EMPTY";
    public const string FoodNameTaken = "FOOD_NAME_TAKEN";
    public const string InvalidOptions = "INVALID_OPTIONS";

    // File
    public const string InvalidFile = "INVALID_FILE";

    // Giỏ hàng / đặt món (lỗi theo từng dòng trả trong extension "items")
    public const string OrderItemsInvalid = "ORDER_ITEMS_INVALID";
    public const string CanteenClosed = "CANTEEN_CLOSED";
    public const string PickupTimeInvalid = "PICKUP_TIME_INVALID";
    public const string TooManyActiveOrders = "TOO_MANY_ACTIVE_ORDERS";
    public const string PaymentMethodUnavailable = "PAYMENT_METHOD_UNAVAILABLE";

    // Đánh giá
    public const string ReviewNotAllowed = "REVIEW_NOT_ALLOWED";
    public const string ReviewWindowClosed = "REVIEW_WINDOW_CLOSED";
    public const string ReviewExists = "REVIEW_EXISTS";
    public const string ReviewHidden = "REVIEW_HIDDEN";

    // Vòng đời đơn
    public const string InvalidStatusTransition = "INVALID_STATUS_TRANSITION";
    public const string PaymentRequired = "PAYMENT_REQUIRED";
    public const string OrderNotCancellable = "ORDER_NOT_CANCELLABLE";

    // Thanh toán
    public const string PaymentProviderError = "PAYMENT_PROVIDER_ERROR";
    public const string PaymentNotPending = "PAYMENT_NOT_PENDING";
    public const string InvalidWebhook = "INVALID_WEBHOOK";
    public const string ItemUnavailable = "ITEM_UNAVAILABLE";
    public const string ItemSoldOut = "ITEM_SOLD_OUT";
    public const string OptionInvalid = "OPTION_INVALID";

    // Voucher
    public const string VoucherInvalid = "VOUCHER_INVALID";
    public const string VoucherExpired = "VOUCHER_EXPIRED";
    public const string VoucherMinOrder = "VOUCHER_MIN_ORDER";
    public const string VoucherExhausted = "VOUCHER_EXHAUSTED";
    public const string VoucherUserLimit = "VOUCHER_USER_LIMIT";
    public const string VoucherCodeTaken = "VOUCHER_CODE_TAKEN";
    public const string VoucherInUse = "VOUCHER_IN_USE";
}
