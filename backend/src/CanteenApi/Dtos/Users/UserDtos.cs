using System.ComponentModel.DataAnnotations;
using CanteenApi.Common;
using CanteenApi.Models;

namespace CanteenApi.Dtos.Users;

// Quy ước: với record, attribute validate đặt trên THAM SỐ constructor.

/// <summary>Biểu thức kiểm tra dùng chung cho module Người dùng.</summary>
public static class UserRules
{
    /// <summary>Mã số sinh viên: đúng 10 chữ số (ví dụ 0023410001).</summary>
    public const string StudentCodePattern = @"^\d{10}$";

    /// <summary>Số điện thoại Việt Nam: 0xxxxxxxxx hoặc +84xxxxxxxxx.</summary>
    public const string PhonePattern = @"^(0|\+84)\d{9}$";
}

/// <summary>Hồ sơ người dùng trả về cho app.</summary>
public sealed record UserProfileDto(
    string Id,
    string Email,
    string FullName,
    string? StudentCode,
    string? Phone,
    string? AvatarUrl,
    UserRole Role,
    bool IsActive,
    DateTime CreatedAt,
    DateTime? LastLoginAt);

/// <summary>Tạo hồ sơ sau khi đăng ký Firebase (email lấy từ token, không lấy từ body).</summary>
public sealed record CreateProfileRequest(
    [Required(ErrorMessage = "Vui lòng nhập họ tên.")]
    [StringLength(100, MinimumLength = 2, ErrorMessage = "Họ tên dài từ 2 đến 100 ký tự.")]
    string FullName,

    [Required(ErrorMessage = "Vui lòng nhập mã số sinh viên.")]
    [RegularExpression(UserRules.StudentCodePattern, ErrorMessage = "Mã số sinh viên gồm đúng 10 chữ số.")]
    string StudentCode,

    [RegularExpression(UserRules.PhonePattern, ErrorMessage = "Số điện thoại không hợp lệ (0xxxxxxxxx hoặc +84xxxxxxxxx).")]
    string? Phone);

/// <summary>Cập nhật hồ sơ của chính mình.</summary>
public sealed record UpdateProfileRequest(
    [Required(ErrorMessage = "Vui lòng nhập họ tên.")]
    [StringLength(100, MinimumLength = 2, ErrorMessage = "Họ tên dài từ 2 đến 100 ký tự.")]
    string FullName,

    [RegularExpression(UserRules.PhonePattern, ErrorMessage = "Số điện thoại không hợp lệ (0xxxxxxxxx hoặc +84xxxxxxxxx).")]
    string? Phone,

    /// <summary>Chỉ được đặt khi hồ sơ chưa có mã số sinh viên; đã có thì không đổi được.</summary>
    [RegularExpression(UserRules.StudentCodePattern, ErrorMessage = "Mã số sinh viên gồm đúng 10 chữ số.")]
    string? StudentCode);

/// <summary>Bộ lọc danh sách người dùng cho admin.</summary>
public sealed class AdminUserQuery : PageQuery
{
    /// <summary>Tìm theo họ tên (không phân biệt dấu), email hoặc mã số sinh viên.</summary>
    [StringLength(100)]
    public string? Search { get; set; }

    public UserRole? Role { get; set; }
    public bool? IsActive { get; set; }
}

/// <summary>Một dòng trong danh sách người dùng (admin).</summary>
public sealed record AdminUserListItemDto(
    string Id,
    string Email,
    string FullName,
    string? StudentCode,
    string? AvatarUrl,
    UserRole Role,
    bool IsActive,
    DateTime CreatedAt,
    DateTime? LastLoginAt);

/// <summary>Chi tiết người dùng (admin), kèm thống kê đơn hàng.</summary>
public sealed record AdminUserDetailDto(
    string Id,
    string Email,
    string FullName,
    string? StudentCode,
    string? Phone,
    string? AvatarUrl,
    UserRole Role,
    bool IsActive,
    DateTime CreatedAt,
    DateTime UpdatedAt,
    DateTime? LastLoginAt,
    int OrderCount,
    int CompletedOrderCount,
    long TotalSpent);

public sealed record UpdateRoleRequest(
    [Required(ErrorMessage = "Vui lòng chọn vai trò (student, staff, admin).")]
    UserRole? Role);

public sealed record UpdateStatusRequest(
    [Required(ErrorMessage = "Vui lòng cho biết trạng thái isActive (true/false).")]
    bool? IsActive);
