namespace CanteenApi.Models;

/// <summary>Danh mục món ăn (Cơm, Mì &amp; Bún, Nước uống...). Bảng SQL Server: Categories.</summary>
public class Category
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;

    /// <summary>Tên Material Icon để Flutter hiển thị biểu tượng danh mục.</summary>
    public string Icon { get; set; } = string.Empty;

    public int SortOrder { get; set; }

    public ICollection<Food> Foods { get; set; } = new List<Food>();
}
