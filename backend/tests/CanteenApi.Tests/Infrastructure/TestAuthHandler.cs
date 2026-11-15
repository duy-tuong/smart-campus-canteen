using System.Security.Claims;
using System.Text.Encodings.Web;
using CanteenApi.Auth;
using CanteenApi.Common;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace CanteenApi.Tests.Infrastructure;

/// <summary>
/// Thay cho xác thực Firebase JWT trong môi trường test: đọc danh tính giả từ header.
///   X-Test-Uid   : uid (bắt buộc; không có → coi như chưa đăng nhập)
///   X-Test-Email : email (tùy chọn)
///   X-Test-Role  : claim role "trong token" (tùy chọn) — dùng để chứng minh backend
///                  KHÔNG tin claim này mà lấy vai trò từ bảng Users.
/// Phần còn lại của pipeline (claims transformation, policy, handler 403) là code thật.
/// </summary>
public sealed class TestAuthHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options,
    ILoggerFactory logger,
    UrlEncoder encoder) : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    public const string SchemeName = "Test";
    public const string UidHeader = "X-Test-Uid";
    public const string EmailHeader = "X-Test-Email";
    public const string RoleHeader = "X-Test-Role";

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!Request.Headers.TryGetValue(UidHeader, out var uid) || string.IsNullOrEmpty(uid))
            return Task.FromResult(AuthenticateResult.NoResult());

        var claims = new List<Claim> { new(AppClaims.UserId, uid.ToString()) };
        if (Request.Headers.TryGetValue(EmailHeader, out var email)) claims.Add(new Claim(AppClaims.Email, email.ToString()));
        if (Request.Headers.TryGetValue(RoleHeader, out var role)) claims.Add(new Claim(AppClaims.Role, role.ToString()));

        var identity = new ClaimsIdentity(claims, SchemeName, AppClaims.UserId, AppClaims.Role);
        return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(identity), SchemeName)));
    }

    /// <summary>Trả 401 dạng ProblemDetails giống JwtBearerEvents.OnChallenge của app thật.</summary>
    protected override Task HandleChallengeAsync(AuthenticationProperties properties) =>
        Problems.WriteAsync(Context, StatusCodes.Status401Unauthorized, ErrorCodes.Unauthorized,
            "Bạn chưa đăng nhập hoặc token không hợp lệ.");
}
