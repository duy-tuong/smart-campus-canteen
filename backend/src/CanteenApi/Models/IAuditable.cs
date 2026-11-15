namespace CanteenApi.Models;

/// <summary>
/// Entity có thời điểm tạo/cập nhật. CanteenDbContext tự gán giá trị (UTC) khi SaveChanges,
/// nên code nghiệp vụ không cần tự set.
/// </summary>
public interface IAuditable
{
    DateTime CreatedAt { get; set; }
    DateTime UpdatedAt { get; set; }
}
