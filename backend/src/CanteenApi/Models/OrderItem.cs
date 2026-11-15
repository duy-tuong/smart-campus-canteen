namespace CanteenApi.Models;

/// <summary>
/// Chi tiết đơn hàng. Bảng: OrderItems.
/// Lưu cứng tên món và giá tại thời điểm đặt, để hóa đơn cũ vẫn đúng khi menu đổi giá/xóa món.
/// Ràng buộc: LineTotal = (UnitPrice + OptionsPrice) * Quantity.
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

    /// <summary>Giá cơ bản của món tại thời điểm đặt.</summary>
    public int UnitPrice { get; set; }

    /// <summary>Tổng giá cộng thêm của các tùy chọn (cho 1 phần).</summary>
    public int OptionsPrice { get; set; }

    public int Quantity { get; set; }
    public int LineTotal { get; set; }

    /// <summary>Ghi chú riêng cho món, ví dụ "ít cay".</summary>
    public string? Note { get; set; }

    public ICollection<OrderItemOption> Options { get; set; } = new List<OrderItemOption>();
}

/// <summary>
/// Tùy chọn đã chọn cho một món trong đơn (bản chụp tên + giá). Bảng: OrderItemOptions.
/// Không đặt khóa ngoại tới FoodOptions: tùy chọn có thể bị sửa/xóa sau này mà hóa đơn vẫn đúng.
/// </summary>
public class OrderItemOption
{
    public int Id { get; set; }

    public int OrderItemId { get; set; }
    public OrderItem? OrderItem { get; set; }

    public string GroupName { get; set; } = string.Empty;
    public string OptionName { get; set; } = string.Empty;
    public int ExtraPrice { get; set; }
}
