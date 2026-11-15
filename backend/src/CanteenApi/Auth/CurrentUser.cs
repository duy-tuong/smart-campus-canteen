using System.Security.Claims;
using CanteenApi.Common;

namespace CanteenApi.Auth;

/// <summary>Thông tin người dùng của request hiện tại (lấy từ ID token đã xác thực).</summary>
public interface ICurrentUser
{
    bool IsAuthenticated { get; }

    /// <summary>Firebase uid. Ném lỗi 401 nếu request chưa đăng nhập.</summary>
    string Uid { get; }

    string? Email { get; }

    /// <summary>Vai trò hiệu lực (đã đối chiếu với bảng Users).</summary>
    string? Role { get; }

    bool IsStaffOrAdmin { get; }
    bool IsAdmin { get; }
}

public sealed class CurrentUser(IHttpContextAccessor accessor) : ICurrentUser
{
    private ClaimsPrincipal? User => accessor.HttpContext?.User;

    public bool IsAuthenticated => User?.Identity?.IsAuthenticated == true;

    public string Uid => User?.FindFirstValue(AppClaims.UserId)
        ?? throw new AppException(StatusCodes.Status401Unauthorized, ErrorCodes.Unauthorized, "Bạn chưa đăng nhập.");

    public string? Email => User?.FindFirstValue(AppClaims.Email);

    public string? Role => User?.FindFirstValue(AppClaims.Role);

    public bool IsStaffOrAdmin => Role is Roles.Staff or Roles.Admin;

    public bool IsAdmin => Role == Roles.Admin;
}
