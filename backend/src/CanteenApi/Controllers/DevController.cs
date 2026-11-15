using System.Text.Json;
using System.Text.Json.Serialization;
using CanteenApi.Auth;
using CanteenApi.Data;
using CanteenApi.Models;
using CanteenApi.Services;
using FirebaseAdmin.Auth;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace CanteenApi.Controllers;

/// <summary>
/// Công cụ khởi tạo dữ liệu cho môi trường phát triển/demo.
/// CHỈ hoạt động khi ASPNETCORE_ENVIRONMENT=Development; môi trường khác trả 404.
/// Không hiển thị trong tài liệu API.
/// </summary>
[ApiController]
[Route("api/dev")]
[ApiExplorerSettings(IgnoreApi = true)]
public class DevController(
    CanteenDbContext db,
    FirebaseDbService rtdb,
    IWebHostEnvironment env,
    ILogger<DevController> logger) : ControllerBase
{
    private static readonly JsonSerializerOptions SeedJson = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter() },
    };

    /// <summary>
    /// POST /api/dev/seed[?reset=true] — nạp menu (danh mục, món, tùy chọn) và voucher từ SeedData/menu.json.
    /// reset=true: XÓA toàn bộ dữ liệu nghiệp vụ (đơn, đánh giá, yêu thích, thông báo, menu, voucher)
    /// ở SQL Server và Firebase RTDB rồi nạp lại. Bảng Users được giữ nguyên.
    /// </summary>
    [HttpPost("seed")]
    public async Task<IActionResult> Seed([FromQuery] bool reset, CancellationToken ct)
    {
        if (!env.IsDevelopment()) return NotFound();

        if (await db.Categories.AnyAsync(ct) || await db.Vouchers.AnyAsync(ct))
        {
            if (!reset)
                return Conflict(new { message = "Đã có dữ liệu. Gọi lại với ?reset=true để xóa và nạp lại." });

            await ResetBusinessDataAsync(ct);
        }

        var seed = await ReadSeedAsync(ct);
        var now = DateTime.UtcNow;

        db.Categories.AddRange(seed.Categories); // EF chèn lồng cả Foods → OptionGroups → Options
        db.Vouchers.AddRange(seed.Vouchers.Select(v => new Voucher
        {
            Code = v.Code.ToUpperInvariant(),
            Description = v.Description,
            DiscountType = v.DiscountType,
            DiscountValue = v.DiscountValue,
            MaxDiscount = v.MaxDiscount,
            MinOrderAmount = v.MinOrderAmount,
            StartAt = now.Date,
            EndAt = now.Date.AddDays(v.ValidDays),
            UsageLimit = v.UsageLimit,
            PerUserLimit = v.PerUserLimit,
        }));
        await db.SaveChangesAsync(ct);

        var result = new
        {
            categories = seed.Categories.Count,
            foods = seed.Categories.Sum(c => c.Foods.Count),
            optionGroups = seed.Categories.SelectMany(c => c.Foods).Sum(f => f.OptionGroups.Count),
            options = seed.Categories.SelectMany(c => c.Foods).SelectMany(f => f.OptionGroups).Sum(g => g.Options.Count),
            vouchers = seed.Vouchers.Count,
        };
        logger.LogInformation("Seeded {@Result}", result);
        return Ok(result);
    }

    /// <summary>
    /// POST /api/dev/accounts — tạo các tài khoản demo (admin, staff, sinh viên) trong Firebase Auth
    /// (nếu chưa có), gán custom claim role và tạo/cập nhật hồ sơ trong bảng Users.
    /// </summary>
    [HttpPost("accounts")]
    public async Task<IActionResult> SeedAccounts(CancellationToken ct)
    {
        if (!env.IsDevelopment()) return NotFound();

        var seed = await ReadSeedAsync(ct);
        var auth = FirebaseAuth.DefaultInstance;
        var results = new List<object>();

        foreach (var acc in seed.Accounts)
        {
            UserRecord user;
            var created = false;
            try
            {
                user = await auth.GetUserByEmailAsync(acc.Email, ct);
            }
            catch (FirebaseAuthException ex) when (ex.AuthErrorCode == AuthErrorCode.UserNotFound)
            {
                user = await auth.CreateUserAsync(new UserRecordArgs
                {
                    Email = acc.Email,
                    Password = acc.Password,
                    DisplayName = acc.FullName,
                    EmailVerified = true,
                }, ct);
                created = true;
            }

            await auth.SetCustomUserClaimsAsync(
                user.Uid, new Dictionary<string, object> { ["role"] = Roles.ToClaim(acc.Role) }, ct);

            var profile = await db.Users.FindAsync([user.Uid], ct);
            if (profile is null)
            {
                profile = new AppUser { Id = user.Uid };
                db.Users.Add(profile);
            }
            profile.Email = acc.Email;
            profile.FullName = acc.FullName;
            profile.StudentCode = acc.StudentCode;
            profile.Phone = acc.Phone;
            profile.Role = acc.Role;
            profile.IsActive = true;

            results.Add(new { acc.Email, role = acc.Role.ToString(), created });
        }

        await db.SaveChangesAsync(ct);
        return Ok(results);
    }

    /// <summary>
    /// POST /api/dev/role?email=...&amp;role=Staff — đổi vai trò một tài khoản đã đăng ký.
    /// Người dùng cần đăng nhập lại (hoặc getIdToken(true)) để token mới có quyền.
    /// </summary>
    [HttpPost("role")]
    public async Task<IActionResult> SetRole([FromQuery] string email, [FromQuery] UserRole role, CancellationToken ct)
    {
        if (!env.IsDevelopment()) return NotFound();

        try
        {
            var user = await FirebaseAuth.DefaultInstance.GetUserByEmailAsync(email, ct);
            await FirebaseAuth.DefaultInstance.SetCustomUserClaimsAsync(
                user.Uid, new Dictionary<string, object> { ["role"] = Roles.ToClaim(role) }, ct);

            var updated = await db.Users.Where(u => u.Id == user.Uid)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(u => u.Role, role)
                    .SetProperty(u => u.UpdatedAt, DateTime.UtcNow), ct);

            return Ok(new { user.Uid, email, role = role.ToString(), profileUpdated = updated > 0 });
        }
        catch (FirebaseAuthException ex) when (ex.AuthErrorCode == AuthErrorCode.UserNotFound)
        {
            return NotFound(new { message = $"Không tìm thấy tài khoản {email}." });
        }
    }

    /// <summary>Xóa dữ liệu nghiệp vụ theo đúng thứ tự khóa ngoại, rồi đặt lại bộ đếm IDENTITY.</summary>
    private async Task ResetBusinessDataAsync(CancellationToken ct)
    {
        await using var tx = await db.Database.BeginTransactionAsync(ct);

        await db.Reviews.ExecuteDeleteAsync(ct);
        await db.Orders.ExecuteDeleteAsync(ct);        // cascade: OrderItems, OrderItemOptions, History, Payments
        await db.Notifications.ExecuteDeleteAsync(ct);
        await db.Favorites.ExecuteDeleteAsync(ct);
        await db.Foods.ExecuteDeleteAsync(ct);         // cascade: FoodOptionGroups, FoodOptions
        await db.Categories.ExecuteDeleteAsync(ct);
        await db.Vouchers.ExecuteDeleteAsync(ct);

        foreach (var table in new[] { "Categories", "Foods", "FoodOptionGroups", "FoodOptions", "Vouchers",
                                      "OrderItems", "OrderItemOptions", "OrderStatusHistory", "Payments",
                                      "Reviews", "Notifications" })
        {
            // Tên bảng là hằng số trong code, không lấy từ input người dùng.
#pragma warning disable EF1002
            await db.Database.ExecuteSqlRawAsync($"DBCC CHECKIDENT ('{table}', RESEED, 0) WITH NO_INFOMSGS;", ct);
#pragma warning restore EF1002
        }

        await tx.CommitAsync(ct);

        // Dọn bản sao realtime trên Firebase để khớp với SQL Server.
        await rtdb.DeleteAsync("orders", ct);
        await rtdb.DeleteAsync("notifications", ct);
    }

    private static async Task<SeedData> ReadSeedAsync(CancellationToken ct)
    {
        var path = Path.Combine(AppContext.BaseDirectory, "SeedData", "menu.json");
        await using var stream = System.IO.File.OpenRead(path);
        return await JsonSerializer.DeserializeAsync<SeedData>(stream, SeedJson, ct)
               ?? throw new InvalidOperationException("menu.json rỗng hoặc sai định dạng.");
    }

    private sealed record SeedData(List<Category> Categories, List<SeedVoucher> Vouchers, List<SeedAccount> Accounts);

    private sealed record SeedVoucher(
        string Code, string Description, DiscountType DiscountType, int DiscountValue,
        int? MaxDiscount, int MinOrderAmount, int ValidDays, int? UsageLimit, int? PerUserLimit);

    private sealed record SeedAccount(
        string Email, string Password, string FullName, UserRole Role,
        string? StudentCode = null, string? Phone = null);
}
