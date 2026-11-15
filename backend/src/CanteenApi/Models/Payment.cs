namespace CanteenApi.Models;

/// <summary>
/// Giao dịch thanh toán của đơn. Bảng: Payments.
/// Một đơn có thể có nhiều giao dịch (thử lại khi thất bại, hoàn tiền khi hủy).
/// </summary>
public class Payment
{
    public int Id { get; set; }

    public string OrderId { get; set; } = string.Empty;
    public Order? Order { get; set; }

    public PaymentMethod Method { get; set; }
    public int Amount { get; set; }
    public PaymentStatus Status { get; set; } = PaymentStatus.Pending;

    /// <summary>Mã giao dịch (chuyển khoản mô phỏng) hoặc mã phiếu thu.</summary>
    public string? TransactionRef { get; set; }

    public DateTime? PaidAt { get; set; }
    public DateTime CreatedAt { get; set; }
}
