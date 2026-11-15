namespace CanteenApi.Models;

/// <summary>Danh mục món ăn (Cơm, Mì &amp; Bún, Nước uống...). Lưu tại RTDB: categories/{id}</summary>
public sealed class Category
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;

    /// <summary>Tên Material Icon để Flutter hiển thị biểu tượng danh mục.</summary>
    public string Icon { get; set; } = string.Empty;

    public int SortOrder { get; set; }
}
