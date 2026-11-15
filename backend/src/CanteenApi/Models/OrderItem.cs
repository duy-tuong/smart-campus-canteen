namespace CanteenApi.Models;

/// <summary>
/// Chi tiết đơn hàng. Bảng SQL Server: OrderItems.
/// Lưu cứng tên món và đơn giá tại thời điểm đặt, để hóa đơn cũ vẫn đúng khi menu đổi giá/xóa món.
/// </summary>
public class OrderItem
{
    public int Id { get; set; }

    public string OrderId { get; set; } = string.Empty;
    public Order? Order { get; set; }

    /// <summary>null nếu món đã bị xóa khỏi thực đơn.</summary>
    public int? FoodId { get; set; }
    public Food? Food { get; set; }

    public string FoodName { get; set; } = string.Empty;
    public int UnitPrice { get; set; }
    public int Quantity { get; set; }
}
