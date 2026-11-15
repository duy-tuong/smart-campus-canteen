namespace CanteenApi.Models;

/// <summary>Món yêu thích của người dùng. Bảng: Favorites, khóa chính kép (UserId, FoodId).</summary>
public class Favorite
{
    public string UserId { get; set; } = string.Empty;
    public AppUser? User { get; set; }

    public int FoodId { get; set; }
    public Food? Food { get; set; }

    public DateTime CreatedAt { get; set; }
}
