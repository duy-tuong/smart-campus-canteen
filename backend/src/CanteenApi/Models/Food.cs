namespace CanteenApi.Models;

/// <summary>Món ăn trong thực đơn. Lưu tại RTDB: foods/{id}</summary>
public sealed class Food
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;

    /// <summary>Giá bán (VNĐ, số nguyên để tránh sai số làm tròn).</summary>
    public int Price { get; set; }

    /// <summary>Đường dẫn ảnh tương đối, ví dụ "/images/com-ga.jpg" (phục vụ từ wwwroot).</summary>
    public string ImageUrl { get; set; } = string.Empty;

    public string CategoryId { get; set; } = string.Empty;

    /// <summary>false = tạm hết món, sinh viên không đặt được.</summary>
    public bool IsAvailable { get; set; } = true;

    public int PrepTimeMinutes { get; set; }
}
