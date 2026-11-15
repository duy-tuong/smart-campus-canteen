using System.Collections.Concurrent;
using CanteenApi.Models;
using CanteenApi.Services.Firebase;

namespace CanteenApi.Tests.Infrastructure;

/// <summary>
/// Bản giả của Firebase Admin: không gọi mạng, chỉ ghi lại các thao tác
/// để test kiểm tra backend đã đồng bộ vai trò/khóa tài khoản sang Firebase hay chưa.
/// </summary>
public sealed class FakeFirebaseAuthService : IFirebaseAuthService
{
    public ConcurrentDictionary<string, UserRole> RoleClaims { get; } = new();
    public ConcurrentDictionary<string, bool> Disabled { get; } = new();

    public void Reset()
    {
        RoleClaims.Clear();
        Disabled.Clear();
    }

    public Task<FirebaseUserInfo?> FindByEmailAsync(string email, CancellationToken ct = default) =>
        Task.FromResult<FirebaseUserInfo?>(null);

    public Task<FirebaseUserInfo> CreateUserAsync(string email, string password, string displayName, CancellationToken ct = default) =>
        Task.FromResult(new FirebaseUserInfo(Guid.NewGuid().ToString("N"), email, false));

    public Task SetRoleClaimAsync(string uid, UserRole role, CancellationToken ct = default)
    {
        RoleClaims[uid] = role;
        return Task.CompletedTask;
    }

    public Task SetDisabledAsync(string uid, bool disabled, CancellationToken ct = default)
    {
        Disabled[uid] = disabled;
        return Task.CompletedTask;
    }
}
