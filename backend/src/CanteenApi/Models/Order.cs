namespace CanteenApi.Models;

/// <summary>Trạng thái chế biến đơn hàng: Received → Cooking → Ready → Completed (hoặc Cancelled).</summary>
public enum OrderStatus
{
    Received,   // Đã nhận
    Cooking,    // Đang nấu
    Ready,      // Mời nhận món
    Completed,  // Đã lấy món
    Cancelled,  // Đã hủy
}

/// <summary>
/// Đơn hàng. Bảng SQL Server: Orders (nguồn dữ liệu chính).
/// Cùng <see cref="Id"/> được dùng làm khóa ở Firebase RTDB (orders/{id}) và SQLite trên điện thoại.
/// </summary>
public class Order
{
    /// <summary>GUID dạng chuỗi do server sinh.</summary>
    public string Id { get; set; } = string.Empty;

    public string UserId { get; set; } = string.Empty;
    public AppUser? User { get; set; }

    /// <summary>Mã ngắn để gọi tên tại quầy, ví dụ "A27".</summary>
    public string PickupCode { get; set; } = string.Empty;

    public OrderStatus Status { get; set; } = OrderStatus.Received;

    /// <summary>Tổng tiền (VNĐ) do SERVER tính từ giá trong bảng Foods.</summary>
    public int TotalAmount { get; set; }

    public int TotalItems { get; set; }
    public string? Note { get; set; }

    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    public ICollection<OrderItem> Items { get; set; } = new List<OrderItem>();
}
