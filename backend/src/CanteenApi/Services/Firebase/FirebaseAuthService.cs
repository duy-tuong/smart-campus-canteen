using CanteenApi.Auth;
using CanteenApi.Models;
using FirebaseAdmin.Auth;

namespace CanteenApi.Services.Firebase;

/// <summary>Thông tin tài khoản Firebase Auth cần cho backend.</summary>
public sealed record FirebaseUserInfo(string Uid, string Email, bool Disabled);

/// <summary>
/// Các thao tác quản trị tài khoản trên Firebase Auth.
/// Tách thành interface để code nghiệp vụ không phụ thuộc trực tiếp SDK và có thể thay bằng bản giả khi test.
/// </summary>
public interface IFirebaseAuthService
{
    /// <summary>Tìm tài khoản theo email; trả về null nếu không tồn tại.</summary>
    Task<FirebaseUserInfo?> FindByEmailAsync(string email, CancellationToken ct = default);

    Task<FirebaseUserInfo> CreateUserAsync(string email, string password, string displayName, CancellationToken ct = default);

    /// <summary>Gán custom claim "role" (Security Rules của Realtime Database đọc claim này).</summary>
    Task SetRoleClaimAsync(string uid, UserRole role, CancellationToken ct = default);

    /// <summary>Khóa/mở tài khoản ngay ở Firebase: tài khoản bị khóa không đăng nhập được.</summary>
    Task SetDisabledAsync(string uid, bool disabled, CancellationToken ct = default);
}

/// <summary>Bản cài đặt thật, bọc Firebase Admin SDK.</summary>
public sealed class FirebaseAuthService(FirebaseCredentialProvider provider) : IFirebaseAuthService
{
    private FirebaseAuth Auth => FirebaseAuth.GetAuth(provider.EnsureApp());

    public async Task<FirebaseUserInfo?> FindByEmailAsync(string email, CancellationToken ct = default)
    {
        try
        {
            return Map(await Auth.GetUserByEmailAsync(email, ct));
        }
        catch (FirebaseAuthException ex) when (ex.AuthErrorCode == AuthErrorCode.UserNotFound)
        {
            return null;
        }
    }

    public async Task<FirebaseUserInfo> CreateUserAsync(string email, string password, string displayName, CancellationToken ct = default)
    {
        var user = await Auth.CreateUserAsync(new UserRecordArgs
        {
            Email = email,
            Password = password,
            DisplayName = displayName,
            EmailVerified = true,
        }, ct);
        return Map(user);
    }

    public Task SetRoleClaimAsync(string uid, UserRole role, CancellationToken ct = default) =>
        Auth.SetCustomUserClaimsAsync(uid, new Dictionary<string, object> { ["role"] = Roles.ToClaim(role) }, ct);

    public Task SetDisabledAsync(string uid, bool disabled, CancellationToken ct = default) =>
        Auth.UpdateUserAsync(new UserRecordArgs { Uid = uid, Disabled = disabled }, ct);

    private static FirebaseUserInfo Map(UserRecord u) => new(u.Uid, u.Email, u.Disabled);
}
