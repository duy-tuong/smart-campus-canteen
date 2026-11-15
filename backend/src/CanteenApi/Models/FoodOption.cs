namespace CanteenApi.Models;

/// <summary>
/// Nhóm tùy chọn của một món, ví dụ "Size" (bắt buộc chọn 1) hay "Topping" (chọn 0–3).
/// Bảng: FoodOptionGroups.
/// </summary>
public class FoodOptionGroup
{
    public int Id { get; set; }

    public int FoodId { get; set; }
    public Food? Food { get; set; }

    public string Name { get; set; } = string.Empty;

    /// <summary>true = bắt buộc chọn ít nhất <see cref="MinSelect"/> tùy chọn.</summary>
    public bool IsRequired { get; set; }

    public int MinSelect { get; set; }
    public int MaxSelect { get; set; } = 1;
    public int SortOrder { get; set; }

    public ICollection<FoodOption> Options { get; set; } = new List<FoodOption>();
}

/// <summary>Một lựa chọn trong nhóm, ví dụ "Size L" (+5.000đ), "Thêm trứng" (+6.000đ). Bảng: FoodOptions.</summary>
public class FoodOption
{
    public int Id { get; set; }

    public int GroupId { get; set; }
    public FoodOptionGroup? Group { get; set; }

    public string Name { get; set; } = string.Empty;

    /// <summary>Giá cộng thêm (VNĐ, ≥ 0).</summary>
    public int ExtraPrice { get; set; }

    public bool IsAvailable { get; set; } = true;
    public int SortOrder { get; set; }
}
