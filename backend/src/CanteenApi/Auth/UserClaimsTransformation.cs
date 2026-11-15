using System.Security.Claims;
using CanteenApi.Data;
using Microsoft.AspNetCore.Authentication;

namespace CanteenApi.Auth;

/// <summary>
/// Chạy sau khi xác thực ID token thành công: đối chiếu bảng Users và
///  - GHI ĐÈ claim "role" bằng vai trò trong SQL Server (nguồn dữ liệu chính).
///    Claim trong Firebase token chỉ được làm mới khi app refresh token (tối đa 1 giờ),
///    còn vai trò trong DB có hiệu lực ngay khi admin thay đổi.
///  - Thêm claim "profile" = active | locked | missing để các policy kiểm tra.
/// </summary>
public sealed class UserClaimsTransformation(CanteenDbContext db, UserAccessCache cache) : IClaimsTransformation
{
    public async Task<ClaimsPrincipal> TransformAsync(ClaimsPrincipal principal)
    {
        // Có thể được gọi nhiều lần trong một request → chỉ biến đổi một lần.
        if (principal.Identity?.IsAuthenticated != true || principal.HasClaim(c => c.Type == AppClaims.Profile))
            return principal;

        var uid = principal.FindFirstValue(AppClaims.UserId);
        if (string.IsNullOrEmpty(uid)) return principal;

        var access = await cache.GetAsync(uid, db);

        var result = principal.Clone();
        var identity = (ClaimsIdentity)result.Identity!;

        foreach (var claim in identity.FindAll(identity.RoleClaimType).ToList())
            identity.RemoveClaim(claim);

        if (access is null)
        {
            identity.AddClaim(new Claim(AppClaims.Profile, AppClaims.ProfileMissing));
        }
        else
        {
            identity.AddClaim(new Claim(identity.RoleClaimType, Roles.ToClaim(access.Role)));
            identity.AddClaim(new Claim(AppClaims.Profile,
                access.IsActive ? AppClaims.ProfileActive : AppClaims.ProfileLocked));
        }

        return result;
    }
}
