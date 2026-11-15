namespace CanteenApi.Models;

/// <summary>
/// Hồ sơ người dùng. Bảng: Users.
/// Khóa chính = Firebase uid: Firebase Auth lo đăng nhập/mật khẩu, SQL Server lưu hồ sơ và phân quyền.
/// </summary>
public class AppUser : IAuditable
{
    public string Id { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;

    /// <summary>Mã số sinh viên (null với staff/admin). Duy nhất nếu có.</summary>
    public string? StudentCode { get; set; }

    public string? Phone { get; set; }
    public string? AvatarUrl { get; set; }

    public UserRole Role { get; set; } = UserRole.Student;

    /// <summary>false = tài khoản bị khóa, không gọi được API.</summary>
    public bool IsActive { get; set; } = true;

    public DateTime? LastLoginAt { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    public ICollection<Order> Orders { get; set; } = new List<Order>();
    public ICollection<Favorite> Favorites { get; set; } = new List<Favorite>();
    public ICollection<Review> Reviews { get; set; } = new List<Review>();
    public ICollection<Notification> Notifications { get; set; } = new List<Notification>();
}
