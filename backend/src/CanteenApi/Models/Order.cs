namespace CanteenApi.Models;

/// <summary>
/// Đơn hàng. Bảng: Orders (nguồn dữ liệu chính).
/// Cùng <see cref="Id"/> được dùng làm khóa ở Firebase RTDB (orders/{id}) và SQLite trên điện thoại.
///
/// Ràng buộc tiền: TotalAmount = Subtotal - DiscountAmount (CHECK trong database).
/// </summary>
public class Order : IAuditable
{
    /// <summary>GUID dạng chuỗi do server sinh.</summary>
    public string Id { get; set; } = string.Empty;

    /// <summary>Mã nhận món: số thứ tự trong ngày (giờ VN), 3 chữ số, ví dụ "015" (hiển thị "#015").</summary>
    public string PickupCode { get; set; } = string.Empty;

    /// <summary>Ngày (giờ Việt Nam) của đơn. UNIQUE(PickupDate, PickupCode): mã nhận món không trùng trong ngày.</summary>
    public DateOnly PickupDate { get; set; }

    /// <summary>
    /// Idempotency key do app gửi (header Idempotency-Key). App gửi lại cùng key khi mạng chập chờn
    /// sẽ nhận lại đơn cũ thay vì tạo đơn trùng. UNIQUE(UserId, ClientRequestId).
    /// </summary>
    public string? ClientRequestId { get; set; }

    public string UserId { get; set; } = string.Empty;
    public AppUser? User { get; set; }

    public int? VoucherId { get; set; }
    public Voucher? Voucher { get; set; }

    /// <summary>Lưu cứng mã voucher tại thời điểm đặt.</summary>
    public string? VoucherCode { get; set; }

    public OrderStatus Status { get; set; } = OrderStatus.Received;

    /// <summary>Tạm tính = tổng LineTotal của các món (VNĐ).</summary>
    public int Subtotal { get; set; }

    public int DiscountAmount { get; set; }

    /// <summary>Số tiền phải trả, do SERVER tính từ giá trong database.</summary>
    public int TotalAmount { get; set; }

    public PaymentMethod PaymentMethod { get; set; } = PaymentMethod.Cash;

    /// <summary>
    /// Trạng thái thanh toán hiện tại (phi chuẩn hóa từ bảng Payments) để bảng đơn của staff
    /// và bản sao realtime trên Firebase đọc nhanh, không phải JOIN.
    /// </summary>
    public PaymentStatus PaymentStatus { get; set; } = PaymentStatus.Pending;

    /// <summary>Thời điểm xác nhận đã thanh toán (bắt buộc khi PaymentStatus = Paid).</summary>
    public DateTime? PaidAt { get; set; }

    /// <summary>Giờ sinh viên hẹn đến lấy; null = lấy ngay khi xong.</summary>
    public DateTime? PickupTime { get; set; }

    /// <summary>Thời điểm dự kiến xong món (hiển thị trên app).</summary>
    public DateTime? EstimatedReadyAt { get; set; }

    public string? Note { get; set; }
    public string? CancelReason { get; set; }

    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    /// <summary>Khóa lạc quan: chống 2 staff cùng đổi trạng thái một đơn.</summary>
    public byte[] RowVersion { get; set; } = [];

    public ICollection<OrderItem> Items { get; set; } = new List<OrderItem>();
    public ICollection<OrderStatusHistory> StatusHistory { get; set; } = new List<OrderStatusHistory>();
    public ICollection<Payment> Payments { get; set; } = new List<Payment>();
    public ICollection<Review> Reviews { get; set; } = new List<Review>();
}
