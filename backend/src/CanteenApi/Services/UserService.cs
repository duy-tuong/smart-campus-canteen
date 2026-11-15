using CanteenApi.Auth;
using CanteenApi.Common;
using CanteenApi.Data;
using CanteenApi.Dtos.Users;
using CanteenApi.Models;
using CanteenApi.Services.Firebase;
using Microsoft.EntityFrameworkCore;

namespace CanteenApi.Services;

/// <summary>Nghiệp vụ module Người dùng: hồ sơ cá nhân và quản trị tài khoản.</summary>
public sealed class UserService(
    CanteenDbContext db,
    IFirebaseAuthService firebaseAuth,
    UserAccessCache accessCache,
    IFileStorage files,
    IPublicUrlBuilder urls,
    TimeProvider clock,
    ILogger<UserService> logger)
{
    // ===================== Hồ sơ của tôi =====================

    /// <summary>
    /// Lấy hồ sơ của chính mình và ghi nhận thời điểm đăng nhập (app gọi khi khởi động).
    /// Chưa có hồ sơ → 404 PROFILE_NOT_FOUND; bị khóa → 403 ACCOUNT_LOCKED.
    /// </summary>
    public async Task<UserProfileDto> GetMeAsync(string uid, CancellationToken ct)
    {
        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == uid, ct)
            ?? throw new NotFoundException("Tài khoản chưa có hồ sơ. Vui lòng hoàn tất thông tin cá nhân.",
                                           ErrorCodes.ProfileNotFound);

        if (!user.IsActive)
            throw new ForbiddenException(ErrorCodes.AccountLocked, "Tài khoản đã bị khóa. Vui lòng liên hệ quản trị viên.");

        // Cập nhật trực tiếp một cột, không đụng UpdatedAt (đăng nhập không phải là sửa hồ sơ).
        var now = clock.GetUtcNow().UtcDateTime;
        await db.Users.Where(u => u.Id == uid)
            .ExecuteUpdateAsync(s => s.SetProperty(u => u.LastLoginAt, now), ct);
        user.LastLoginAt = now;

        return ToProfileDto(user);
    }

    /// <summary>
    /// Tạo hồ sơ sinh viên sau khi đăng ký Firebase. Gọi lại khi đã có hồ sơ thì trả hồ sơ cũ (idempotent),
    /// để app có thể thử lại an toàn khi mạng chập chờn.
    /// </summary>
    public async Task<(UserProfileDto Profile, bool Created)> CreateMeAsync(
        string uid, string? email, CreateProfileRequest request, CancellationToken ct)
    {
        var existing = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == uid, ct);
        if (existing is not null) return (ToProfileDto(existing), false);

        if (string.IsNullOrWhiteSpace(email))
            throw new BadRequestException(ErrorCodes.ValidationError, "Tài khoản Firebase chưa có email.");

        var studentCode = request.StudentCode.Trim();
        await EnsureStudentCodeAvailableAsync(studentCode, uid, ct);

        var user = new AppUser
        {
            Id = uid,
            Email = email.Trim().ToLowerInvariant(),
            FullName = NormalizeName(request.FullName),
            StudentCode = studentCode,
            Phone = NormalizeOptional(request.Phone),
            Role = UserRole.Student, // tự đăng ký luôn là sinh viên; staff/admin do admin cấp
            IsActive = true,
            LastLoginAt = clock.GetUtcNow().UtcDateTime,
        };
        db.Users.Add(user);
        await db.SaveChangesAsync(ct);

        accessCache.Invalidate(uid);
        logger.LogInformation("Created profile for {Uid} ({Email})", uid, user.Email);
        return (ToProfileDto(user), true);
    }

    /// <summary>Sửa họ tên, số điện thoại; mã số sinh viên chỉ được đặt khi đang trống.</summary>
    public async Task<UserProfileDto> UpdateMeAsync(string uid, UpdateProfileRequest request, CancellationToken ct)
    {
        var user = await FindAsync(uid, ct);

        user.FullName = NormalizeName(request.FullName);
        user.Phone = NormalizeOptional(request.Phone);

        var newCode = NormalizeOptional(request.StudentCode);
        if (newCode is not null && newCode != user.StudentCode)
        {
            if (user.StudentCode is not null)
                throw new BusinessRuleException(ErrorCodes.StudentCodeLocked,
                    "Mã số sinh viên đã được xác nhận, không thể thay đổi. Liên hệ quản trị viên nếu cần sửa.");

            await EnsureStudentCodeAvailableAsync(newCode, uid, ct);
            user.StudentCode = newCode;
        }

        await db.SaveChangesAsync(ct);
        return ToProfileDto(user);
    }

    /// <summary>Thay ảnh đại diện: lưu file mới, xóa file cũ.</summary>
    public async Task<UserProfileDto> UpdateAvatarAsync(string uid, IFormFile file, CancellationToken ct)
    {
        var user = await FindAsync(uid, ct);
        var oldPath = user.AvatarUrl;

        user.AvatarUrl = await files.SaveImageAsync(file, UploadFolder.Avatars, FileStorageService.MaxAvatarBytes, ct);
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch
        {
            files.Delete(user.AvatarUrl); // lưu DB thất bại → không để lại file mồ côi
            throw;
        }

        files.Delete(oldPath);
        return ToProfileDto(user);
    }

    /// <summary>Gỡ ảnh đại diện.</summary>
    public async Task RemoveAvatarAsync(string uid, CancellationToken ct)
    {
        var user = await FindAsync(uid, ct);
        if (user.AvatarUrl is null) return;

        var oldPath = user.AvatarUrl;
        user.AvatarUrl = null;
        await db.SaveChangesAsync(ct);
        files.Delete(oldPath);
    }

    // ===================== Quản trị (admin) =====================

    public async Task<PagedResult<AdminUserListItemDto>> ListAsync(AdminUserQuery query, CancellationToken ct)
    {
        var users = db.Users.AsNoTracking();

        if (!string.IsNullOrWhiteSpace(query.Search))
        {
            var term = query.Search.Trim();
            users = users.Where(u =>
                // Tìm không dấu, không phân biệt hoa/thường ("nguyen van an" khớp "Nguyễn Văn An").
                EF.Functions.Collate(u.FullName, SearchCollation.AccentInsensitive).Contains(term) ||
                u.Email.Contains(term) ||
                (u.StudentCode != null && u.StudentCode.Contains(term)));
        }

        if (query.Role is { } role) users = users.Where(u => u.Role == role);
        if (query.IsActive is { } active) users = users.Where(u => u.IsActive == active);

        var page = await users
            .OrderByDescending(u => u.CreatedAt).ThenBy(u => u.Email)
            .Select(u => new AdminUserListItemDto(
                u.Id, u.Email, u.FullName, u.StudentCode, u.AvatarUrl,
                u.Role, u.IsActive, u.CreatedAt, u.LastLoginAt))
            .ToPagedResultAsync(query, ct);

        return page with { Items = page.Items.Select(i => i with { AvatarUrl = urls.Build(i.AvatarUrl) }).ToList() };
    }

    public async Task<AdminUserDetailDto> GetDetailAsync(string id, CancellationToken ct)
    {
        var detail = await db.Users.AsNoTracking()
            .Where(u => u.Id == id)
            .Select(u => new AdminUserDetailDto(
                u.Id, u.Email, u.FullName, u.StudentCode, u.Phone, u.AvatarUrl,
                u.Role, u.IsActive, u.CreatedAt, u.UpdatedAt, u.LastLoginAt,
                u.Orders.Count(),
                u.Orders.Count(o => o.Status == OrderStatus.Completed),
                u.Orders.Where(o => o.Status == OrderStatus.Completed).Sum(o => (long)o.TotalAmount)))
            .FirstOrDefaultAsync(ct)
            ?? throw new NotFoundException("Không tìm thấy người dùng.");

        return detail with { AvatarUrl = urls.Build(detail.AvatarUrl) };
    }

    /// <summary>
    /// Đổi vai trò: cập nhật custom claim trên Firebase (cho Security Rules) rồi cập nhật SQL Server
    /// (nguồn quyết định quyền gọi API), xóa cache để có hiệu lực ngay.
    /// </summary>
    public async Task<AdminUserDetailDto> ChangeRoleAsync(string actorUid, string id, UserRole role, CancellationToken ct)
    {
        EnsureNotSelf(actorUid, id, "Không thể tự thay đổi vai trò của chính mình.");
        var user = await FindAsync(id, ct);

        if (user.Role != role)
        {
            await firebaseAuth.SetRoleClaimAsync(id, role, ct);
            user.Role = role;
            await db.SaveChangesAsync(ct);
            accessCache.Invalidate(id);
            logger.LogInformation("Admin {Actor} changed role of {User} to {Role}", actorUid, id, role);
        }

        return await GetDetailAsync(id, ct);
    }

    /// <summary>
    /// Khóa/mở tài khoản: vô hiệu hóa luôn trên Firebase (không đăng nhập được nữa)
    /// và trên SQL Server (token cũ còn hạn cũng bị chặn ngay ở request kế tiếp).
    /// </summary>
    public async Task<AdminUserDetailDto> ChangeStatusAsync(string actorUid, string id, bool isActive, CancellationToken ct)
    {
        EnsureNotSelf(actorUid, id, "Không thể tự khóa tài khoản của chính mình.");
        var user = await FindAsync(id, ct);

        if (user.IsActive != isActive)
        {
            await firebaseAuth.SetDisabledAsync(id, !isActive, ct);
            user.IsActive = isActive;
            await db.SaveChangesAsync(ct);
            accessCache.Invalidate(id);
            logger.LogInformation("Admin {Actor} set IsActive={Active} for {User}", actorUid, isActive, id);
        }

        return await GetDetailAsync(id, ct);
    }

    // ===================== Hỗ trợ =====================

    private async Task<AppUser> FindAsync(string uid, CancellationToken ct) =>
        await db.Users.FirstOrDefaultAsync(u => u.Id == uid, ct)
        ?? throw new NotFoundException("Không tìm thấy người dùng.");

    private async Task EnsureStudentCodeAvailableAsync(string studentCode, string uid, CancellationToken ct)
    {
        if (await db.Users.AnyAsync(u => u.StudentCode == studentCode && u.Id != uid, ct))
            throw new ConflictException(ErrorCodes.StudentCodeTaken, $"Mã số sinh viên {studentCode} đã được sử dụng.");
    }

    private static void EnsureNotSelf(string actorUid, string targetUid, string message)
    {
        if (actorUid == targetUid) throw new ForbiddenException(ErrorCodes.CannotModifySelf, message);
    }

    /// <summary>Bỏ khoảng trắng thừa: "  nguyễn   văn  an " → "nguyễn văn an".</summary>
    private static string NormalizeName(string name) =>
        string.Join(' ', name.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));

    private static string? NormalizeOptional(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private UserProfileDto ToProfileDto(AppUser u) => new(
        u.Id, u.Email, u.FullName, u.StudentCode, u.Phone, urls.Build(u.AvatarUrl),
        u.Role, u.IsActive, u.CreatedAt, u.LastLoginAt);
}
