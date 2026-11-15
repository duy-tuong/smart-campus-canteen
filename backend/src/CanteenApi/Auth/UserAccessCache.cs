using CanteenApi.Data;
using CanteenApi.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;

namespace CanteenApi.Auth;

/// <summary>Vai trò và trạng thái của một người dùng tại thời điểm đọc từ bảng Users.</summary>
public sealed record UserAccess(UserRole Role, bool IsActive);

/// <summary>
/// Cache ngắn hạn (60 giây) thông tin phân quyền của người dùng, tránh truy vấn bảng Users ở mọi request.
/// Khi admin đổi vai trò/khóa tài khoản hoặc người dùng vừa tạo hồ sơ, gọi <see cref="Invalidate"/>
/// để thay đổi có hiệu lực ngay ở request kế tiếp.
/// </summary>
public sealed class UserAccessCache(IMemoryCache cache)
{
    private static readonly TimeSpan Ttl = TimeSpan.FromSeconds(60);

    /// <summary>Trả về null nếu người dùng chưa có hồ sơ.</summary>
    public async Task<UserAccess?> GetAsync(string uid, CanteenDbContext db, CancellationToken ct = default)
    {
        if (cache.TryGetValue(Key(uid), out UserAccess? cached)) return cached;

        var access = await db.Users.AsNoTracking()
            .Where(u => u.Id == uid)
            .Select(u => new UserAccess(u.Role, u.IsActive))
            .FirstOrDefaultAsync(ct);

        // Chỉ cache khi đã có hồ sơ: người vừa đăng ký sẽ tạo hồ sơ ngay sau đó.
        if (access is not null) cache.Set(Key(uid), access, Ttl);
        return access;
    }

    public void Invalidate(string uid) => cache.Remove(Key(uid));

    private static string Key(string uid) => $"user-access:{uid}";
}
