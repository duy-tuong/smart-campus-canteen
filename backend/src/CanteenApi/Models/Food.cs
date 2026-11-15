namespace CanteenApi.Models;

/// <summary>Món ăn trong thực đơn. Bảng: Foods.</summary>
public class Food : IAuditable
{
    public int Id { get; set; }

    public int CategoryId { get; set; }
    public Category? Category { get; set; }

    public string Name { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;

    /// <summary>Giá cơ bản (VNĐ, số nguyên để tránh sai số làm tròn).</summary>
    public int Price { get; set; }

    /// <summary>Đường dẫn ảnh tương đối, ví dụ "/images/com-ga.jpg" (phục vụ từ wwwroot).</summary>
    public string? ImageUrl { get; set; }

    public int PrepTimeMinutes { get; set; }

    /// <summary>Số suất tối đa bán mỗi ngày; null = không giới hạn.</summary>
    public int? DailyLimit { get; set; }

    /// <summary>false = tạm hết món, sinh viên không đặt được.</summary>
    public bool IsAvailable { get; set; } = true;

    /// <summary>Điểm đánh giá trung bình (0–5), cập nhật khi có Review mới (phi chuẩn hóa để đọc nhanh).</summary>
    public decimal AverageRating { get; set; }

    public int RatingCount { get; set; }

    /// <summary>Xóa mềm: món đã từng bán không xóa vật lý để thống kê doanh thu vẫn đúng.</summary>
    public bool IsDeleted { get; set; }

    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    /// <summary>Khóa lạc quan: chống 2 staff cùng sửa một món ghi đè lên nhau.</summary>
    public byte[] RowVersion { get; set; } = [];

    public ICollection<FoodOptionGroup> OptionGroups { get; set; } = new List<FoodOptionGroup>();
    public ICollection<Review> Reviews { get; set; } = new List<Review>();
}
