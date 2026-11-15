namespace CanteenApi.Services.Payments;

/// <summary>Trạng thái link thanh toán phía cổng thanh toán.</summary>
public enum GatewayLinkStatus
{
    Pending,
    Processing,
    Paid,
    Underpaid,
    Cancelled,
    Expired,
    Failed,
}

public sealed record CreatePaymentLinkInput(
    long OrderCode,
    int Amount,
    string Description,
    string ReturnUrl,
    string CancelUrl,
    DateTime ExpiresAtUtc,
    string? BuyerName);

public sealed record PaymentLinkResult(
    string PaymentLinkId,
    string CheckoutUrl,
    string QrCode,
    string Description,
    string BankBin,
    string AccountNumber,
    string AccountName);

/// <summary>Trạng thái hiện tại của link (khi đồng bộ chủ động).</summary>
public sealed record GatewayPaymentStatus(
    GatewayLinkStatus Status,
    long Amount,
    long AmountPaid,
    /// <summary>Mã giao dịch ngân hàng của lần chuyển gần nhất (nếu có).</summary>
    string? Reference,
    DateTime? PaidAtUtc);

/// <summary>Dữ liệu webhook ĐÃ được xác thực chữ ký.</summary>
public sealed record VerifiedPaymentWebhook(
    long OrderCode,
    long Amount,
    string Reference,
    DateTime? PaidAtUtc,
    /// <summary>"00" = giao dịch thành công.</summary>
    string Code);

/// <summary>Chữ ký webhook không hợp lệ (giả mạo hoặc sai checksum key).</summary>
public sealed class InvalidWebhookException(string message) : Exception(message);

/// <summary>
/// Cổng thanh toán. Code nghiệp vụ chỉ phụ thuộc interface này (không phụ thuộc SDK payOS),
/// nên test dùng bản giả và có thể đổi sang cổng khác mà không sửa nghiệp vụ.
/// </summary>
public interface IPaymentGateway
{
    /// <summary>Đã cấu hình đủ khóa và được bật.</summary>
    bool IsEnabled { get; }

    Task<PaymentLinkResult> CreateLinkAsync(CreatePaymentLinkInput input, CancellationToken ct);

    Task<GatewayPaymentStatus> GetStatusAsync(long orderCode, CancellationToken ct);

    Task CancelLinkAsync(long orderCode, string reason, CancellationToken ct);

    /// <summary>Xác thực chữ ký webhook trên NỘI DUNG GỐC của request. Sai chữ ký → <see cref="InvalidWebhookException"/>.</summary>
    Task<VerifiedPaymentWebhook> VerifyWebhookAsync(string rawBody);

    /// <summary>Đăng ký URL webhook với cổng thanh toán. Trả về tên tài khoản nhận tiền.</summary>
    Task<string> ConfirmWebhookUrlAsync(string url, CancellationToken ct);
}
