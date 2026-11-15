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

    /// <summary>Mã ngắn để gọi tên tại quầy, ví dụ "A27".</summary>
    public string PickupCode { get; set; } = string.Empty;

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
