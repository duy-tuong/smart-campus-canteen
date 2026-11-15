namespace CanteenApi.Models;

/// <summary>
/// Nhật ký đổi trạng thái đơn (ai đổi, lúc nào). Bảng: OrderStatusHistory.
/// Dùng để vẽ dòng thời gian trên app và truy vết khi có khiếu nại.
/// </summary>
public class OrderStatusHistory
{
    public long Id { get; set; }

    public string OrderId { get; set; } = string.Empty;
    public Order? Order { get; set; }

    /// <summary>null với bản ghi đầu tiên (lúc tạo đơn).</summary>
    public OrderStatus? FromStatus { get; set; }

    public OrderStatus ToStatus { get; set; }

    /// <summary>Người đổi trạng thái; null = hệ thống tự động (ví dụ tự hủy đơn quá hạn thanh toán).</summary>
    public string? ChangedByUserId { get; set; }
    public AppUser? ChangedByUser { get; set; }

    public string? Note { get; set; }
    public DateTime ChangedAt { get; set; }
}
