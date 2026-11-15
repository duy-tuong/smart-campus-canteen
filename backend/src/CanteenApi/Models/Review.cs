namespace CanteenApi.Models;

/// <summary>
/// Đánh giá món sau khi nhận. Bảng: Reviews.
/// Mỗi món trong một đơn chỉ được đánh giá một lần: UNIQUE(OrderId, FoodId).
/// </summary>
public class Review : IAuditable
{
    public int Id { get; set; }

    public string UserId { get; set; } = string.Empty;
    public AppUser? User { get; set; }

    public int FoodId { get; set; }
    public Food? Food { get; set; }

    public string OrderId { get; set; } = string.Empty;
    public Order? Order { get; set; }

    /// <summary>Số sao 1–5.</summary>
    public byte Rating { get; set; }

    public string? Comment { get; set; }

    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}
