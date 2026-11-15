namespace CanteenApi.Models;

/// <summary>
/// Giao dịch thanh toán của đơn. Bảng: Payments.
/// Một đơn có thể có nhiều giao dịch (thanh toán; hoàn tiền khi hủy đơn đã trả).
/// </summary>
public class Payment
{
    public int Id { get; set; }

    public string OrderId { get; set; } = string.Empty;
    public Order? Order { get; set; }

    public PaymentMethod Method { get; set; }
    public int Amount { get; set; }
    public PaymentStatus Status { get; set; } = PaymentStatus.Pending;

    /// <summary>
    /// Mã tham chiếu giao dịch: mã giao dịch ngân hàng (payOS), "CASH-..." (tiền mặt), "MANUAL-..." (staff xác nhận).
    /// UNIQUE có lọc: cùng một giao dịch ngân hàng không thể được ghi nhận hai lần.
    /// </summary>
    public string? TransactionRef { get; set; }

    public DateTime? PaidAt { get; set; }
    public DateTime CreatedAt { get; set; }

    // ----- payOS (chỉ với chuyển khoản) -----

    /// <summary>orderCode gửi sang payOS (số nguyên, duy nhất). UNIQUE có lọc.</summary>
    public long? ProviderOrderCode { get; set; }

    /// <summary>Mã link thanh toán do payOS cấp.</summary>
    public string? PaymentLinkId { get; set; }

    /// <summary>Trang thanh toán của payOS (mở bằng trình duyệt).</summary>
    public string? CheckoutUrl { get; set; }

    /// <summary>Chuỗi VietQR để app tự vẽ mã QR.</summary>
    public string? QrCode { get; set; }

    /// <summary>Hạn của link thanh toán.</summary>
    public DateTime? ExpiresAt { get; set; }

    /// <summary>Nội dung chuyển khoản (≤ 9 ký tự, ví dụ "SC1160001") — để người dùng tự chuyển khi không quét được QR.</summary>
    public string? TransferContent { get; set; }

    /// <summary>Mã BIN ngân hàng nhận tiền (VietQR).</summary>
    public string? BankBin { get; set; }

    public string? BankAccountNumber { get; set; }
    public string? BankAccountName { get; set; }
}
