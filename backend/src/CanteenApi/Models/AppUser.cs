namespace CanteenApi.Models;

/// <summary>
/// Hồ sơ người dùng. Bảng SQL Server: Users.
/// Khóa chính = Firebase uid (Firebase Auth lo đăng nhập; SQL Server lưu thông tin hồ sơ).
/// </summary>
public class AppUser
{
    public string Id { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public string StudentId { get; set; } = string.Empty;

    /// <summary>"student" hoặc "staff" (đồng bộ với custom claim role của Firebase).</summary>
    public string Role { get; set; } = "student";

    public DateTime CreatedAt { get; set; }

    public ICollection<Order> Orders { get; set; } = new List<Order>();
}
