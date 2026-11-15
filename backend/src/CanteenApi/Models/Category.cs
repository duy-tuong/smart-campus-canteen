namespace CanteenApi.Models;

/// <summary>Danh mục món ăn (Cơm, Mì &amp; Bún, Nước uống...). Bảng: Categories.</summary>
public class Category : IAuditable
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }

    /// <summary>Tên Material Icon để Flutter hiển thị biểu tượng danh mục.</summary>
    public string Icon { get; set; } = string.Empty;

    public int SortOrder { get; set; }

    /// <summary>false = tạm ẩn khỏi menu của sinh viên.</summary>
    public bool IsActive { get; set; } = true;

    /// <summary>Xóa mềm: giữ lại để thống kê/hóa đơn cũ không bị ảnh hưởng.</summary>
    public bool IsDeleted { get; set; }

    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    public ICollection<Food> Foods { get; set; } = new List<Food>();
}
