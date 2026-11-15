using CanteenApi.Models;

namespace CanteenApi.Auth;

/// <summary>Giá trị claim "role" (khớp với custom claim trong Firebase ID token và Security Rules).</summary>
public static class Roles
{
    public const string Student = "student";
    public const string Staff = "staff";
    public const string Admin = "admin";

    public static string ToClaim(UserRole role) => role switch
    {
        UserRole.Staff => Staff,
        UserRole.Admin => Admin,
        _ => Student,
    };
}

/// <summary>Tên các claim nội bộ backend thêm vào sau khi đối chiếu bảng Users.</summary>
public static class AppClaims
{
    /// <summary>Uid Firebase (claim chuẩn trong ID token).</summary>
    public const string UserId = "user_id";
    public const string Email = "email";
    public const string Role = "role";

    /// <summary>Trạng thái hồ sơ trong SQL Server: active | locked | missing.</summary>
    public const string Profile = "profile";

    public const string ProfileActive = "active";
    public const string ProfileLocked = "locked";
    public const string ProfileMissing = "missing";
}
