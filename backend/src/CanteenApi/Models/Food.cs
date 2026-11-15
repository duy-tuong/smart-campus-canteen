namespace CanteenApi.Models;

/// <summary>Món ăn trong thực đơn. Bảng SQL Server: Foods.</summary>
public class Food
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;

    /// <summary>Giá bán (VNĐ, số nguyên để tránh sai số làm tròn).</summary>
    public int Price { get; set; }

    /// <summary>Đường dẫn ảnh tương đối, ví dụ "/images/com-ga.jpg" (phục vụ từ wwwroot).</summary>
    public string ImageUrl { get; set; } = string.Empty;

    public int CategoryId { get; set; }
    public Category? Category { get; set; }

    /// <summary>false = tạm hết món, sinh viên không đặt được.</summary>
    public bool IsAvailable { get; set; } = true;

    public int PrepTimeMinutes { get; set; }

    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}
