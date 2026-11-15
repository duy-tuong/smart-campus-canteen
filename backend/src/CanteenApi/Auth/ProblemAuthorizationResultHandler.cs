using CanteenApi.Common;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Authorization.Policy;

namespace CanteenApi.Auth;

/// <summary>
/// Trả lỗi 403 dạng ProblemDetails với mã lỗi cụ thể, để app biết phải làm gì:
///  - PROFILE_NOT_FOUND → chuyển tới màn "Hoàn tất hồ sơ"
///  - ACCOUNT_LOCKED    → báo tài khoản bị khóa và đăng xuất
///  - FORBIDDEN         → không đủ quyền (ví dụ sinh viên gọi API của staff)
/// Lỗi 401 (thiếu/sai token) do JwtBearerEvents.OnChallenge xử lý.
/// </summary>
public sealed class ProblemAuthorizationResultHandler : IAuthorizationMiddlewareResultHandler
{
    private readonly AuthorizationMiddlewareResultHandler _default = new();

    public Task HandleAsync(RequestDelegate next, HttpContext http, AuthorizationPolicy policy, PolicyAuthorizationResult result)
    {
        if (!result.Forbidden)
            return _default.HandleAsync(next, http, policy, result);

        var profile = http.User.FindFirst(AppClaims.Profile)?.Value;
        return profile switch
        {
            AppClaims.ProfileMissing => Problems.WriteAsync(http, StatusCodes.Status403Forbidden, ErrorCodes.ProfileNotFound,
                "Tài khoản chưa có hồ sơ. Vui lòng hoàn tất thông tin cá nhân."),
            AppClaims.ProfileLocked => Problems.WriteAsync(http, StatusCodes.Status403Forbidden, ErrorCodes.AccountLocked,
                "Tài khoản đã bị khóa. Vui lòng liên hệ quản trị viên."),
            _ => Problems.WriteAsync(http, StatusCodes.Status403Forbidden, ErrorCodes.Forbidden,
                "Bạn không có quyền thực hiện thao tác này."),
        };
    }
}
