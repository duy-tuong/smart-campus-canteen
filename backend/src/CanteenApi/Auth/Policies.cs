using Microsoft.AspNetCore.Authorization;

namespace CanteenApi.Auth;

/// <summary>
/// Các chính sách phân quyền.
///
/// - Mặc định (FallbackPolicy) mọi endpoint đều yêu cầu <see cref="ActiveUser"/>:
///   quên gắn [Authorize] cũng không bị lộ API.
/// - Endpoint công khai phải ghi rõ [AllowAnonymous].
/// </summary>
public static class Policies
{
    /// <summary>Chỉ cần ID token hợp lệ (dùng khi người dùng chưa tạo hồ sơ).</summary>
    public const string SignedIn = "SignedIn";

    /// <summary>Token hợp lệ + đã có hồ sơ trong SQL Server + tài khoản không bị khóa.</summary>
    public const string ActiveUser = "ActiveUser";

    /// <summary>ActiveUser với vai trò staff hoặc admin (quản lý căn-tin).</summary>
    public const string StaffOrAdmin = "StaffOrAdmin";

    /// <summary>ActiveUser với vai trò admin (quản trị hệ thống).</summary>
    public const string AdminOnly = "AdminOnly";

    public static IServiceCollection AddAppAuthorization(this IServiceCollection services)
    {
        var activeUser = new AuthorizationPolicyBuilder()
            .RequireAuthenticatedUser()
            .RequireClaim(AppClaims.Profile, AppClaims.ProfileActive)
            .Build();

        services.AddAuthorizationBuilder()
            .AddPolicy(SignedIn, p => p.RequireAuthenticatedUser())
            .AddPolicy(ActiveUser, activeUser)
            .AddPolicy(StaffOrAdmin, p => p.Combine(activeUser).RequireRole(Roles.Staff, Roles.Admin))
            .AddPolicy(AdminOnly, p => p.Combine(activeUser).RequireRole(Roles.Admin))
            .SetDefaultPolicy(activeUser)   // [Authorize] không ghi policy
            .SetFallbackPolicy(activeUser); // endpoint không gắn attribute nào

        return services;
    }
}
