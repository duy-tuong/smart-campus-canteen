using System.ComponentModel.DataAnnotations;
using System.Text.Json;
using System.Text.Json.Serialization;
using CanteenApi.Auth;
using CanteenApi.Common;
using CanteenApi.Data;
using CanteenApi.Models;
using CanteenApi.Options;
using CanteenApi.Services;
using CanteenApi.Services.Firebase;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace CanteenApi.Controllers;

/// <summary>
/// Công cụ cho môi trường phát triển/demo: nạp dữ liệu mẫu, tạo tài khoản demo, lấy token để thử API.
/// CHỈ hoạt động khi ASPNETCORE_ENVIRONMENT=Development; môi trường khác trả 404.
/// Các endpoint nạp dữ liệu không hiển thị trong tài liệu API.
/// </summary>
[ApiController]
[Route("api/dev")]
[Tags("Dev (chỉ môi trường Development)")]
public class DevController(
    CanteenDbContext db,
    FirebaseDbService rtdb,
    IFirebaseAuthService firebaseAuth,
    UserAccessCache accessCache,
    IHttpClientFactory httpClientFactory,
    IOptions<FirebaseOptions> firebaseOptions,
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
    [AllowAnonymous]
    [ApiExplorerSettings(IgnoreApi = true)]
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
    /// (nếu chưa có), mở khóa, gán custom claim role và tạo/cập nhật hồ sơ trong bảng Users.
    /// Chạy lại nhiều lần không tạo trùng.
    /// </summary>
    [HttpPost("accounts")]
    [AllowAnonymous]
    [ApiExplorerSettings(IgnoreApi = true)]
    public async Task<IActionResult> SeedAccounts(CancellationToken ct)
    {
        if (!env.IsDevelopment()) return NotFound();

        var seed = await ReadSeedAsync(ct);
        var results = new List<object>();

        foreach (var acc in seed.Accounts)
        {
            var user = await firebaseAuth.FindByEmailAsync(acc.Email, ct);
            var created = user is null;
            user ??= await firebaseAuth.CreateUserAsync(acc.Email, acc.Password, acc.FullName, ct);

            if (user.Disabled) await firebaseAuth.SetDisabledAsync(user.Uid, false, ct);
            await firebaseAuth.SetRoleClaimAsync(user.Uid, acc.Role, ct);

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

            accessCache.Invalidate(user.Uid);
            results.Add(new { acc.Email, role = acc.Role.ToString(), created });
        }

        await db.SaveChangesAsync(ct);
        return Ok(results);
    }

    /// <summary>
    /// POST /api/dev/role?email=...&amp;role=Staff — đổi vai trò một tài khoản đã đăng ký.
    /// Có hiệu lực ngay với API (vai trò đọc từ DB); Security Rules của Firebase nhận claim mới
    /// khi app làm mới token (getIdToken(true)).
    /// </summary>
    [HttpPost("role")]
    [AllowAnonymous]
    [ApiExplorerSettings(IgnoreApi = true)]
    public async Task<IActionResult> SetRole([FromQuery] string email, [FromQuery] UserRole role, CancellationToken ct)
    {
        if (!env.IsDevelopment()) return NotFound();

        var user = await firebaseAuth.FindByEmailAsync(email, ct);
        if (user is null) return NotFound(new { message = $"Không tìm thấy tài khoản {email}." });

        await firebaseAuth.SetRoleClaimAsync(user.Uid, role, ct);
        var updated = await db.Users.Where(u => u.Id == user.Uid)
            .ExecuteUpdateAsync(s => s
                .SetProperty(u => u.Role, role)
                .SetProperty(u => u.UpdatedAt, DateTime.UtcNow), ct);
        accessCache.Invalidate(user.Uid);

        return Ok(new { user.Uid, email, role = role.ToString(), profileUpdated = updated > 0 });
    }

    /// <summary>
    /// Đăng nhập bằng email/mật khẩu (qua Firebase Auth REST) và trả về ID token để thử API trên Scalar.
    /// Ví dụ: sv01@smartcanteen.vn / Canteen@123. Token có hạn 1 giờ.
    /// </summary>
    [HttpPost("token")]
    [AllowAnonymous]
    [ProducesResponseType<DevTokenResponse>(StatusCodes.Status200OK)]
    public async Task<IActionResult> GetToken([FromBody] DevTokenRequest request, CancellationToken ct)
    {
        if (!env.IsDevelopment()) return NotFound();

        var apiKey = firebaseOptions.Value.WebApiKey;
        if (string.IsNullOrWhiteSpace(apiKey))
            throw new BadRequestException(ErrorCodes.ValidationError,
                "Chưa cấu hình Firebase:WebApiKey trong user-secrets (xem README).");

        var http = httpClientFactory.CreateClient();
        using var response = await http.PostAsJsonAsync(
            $"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={apiKey}",
            new { email = request.Email, password = request.Password, returnSecureToken = true }, ct);

        if (!response.IsSuccessStatusCode)
            throw new AppException(StatusCodes.Status401Unauthorized, ErrorCodes.Unauthorized,
                "Sai email/mật khẩu hoặc tài khoản đã bị khóa.");

        var body = await response.Content.ReadFromJsonAsync<FirebaseSignInResponse>(ct)
                   ?? throw new InvalidOperationException("Firebase không trả về token.");
        return Ok(new DevTokenResponse(body.IdToken, body.LocalId, int.Parse(body.ExpiresIn)));
    }

    /// <summary>
    /// Kiểm tra phân quyền: trả về người dùng hiện tại (vai trò lấy từ SQL Server).
    /// Yêu cầu tài khoản đã có hồ sơ và không bị khóa.
    /// </summary>
    [HttpGet("whoami")]
    public IActionResult WhoAmI([FromServices] ICurrentUser me)
    {
        if (!env.IsDevelopment()) return NotFound();
        return Ok(new { me.Uid, me.Email, me.Role });
    }

    /// <summary>Kiểm tra policy StaffOrAdmin (sinh viên gọi sẽ nhận 403 FORBIDDEN).</summary>
    [HttpGet("staff-only")]
    [Authorize(Policy = Policies.StaffOrAdmin)]
    public IActionResult StaffOnly([FromServices] ICurrentUser me)
    {
        if (!env.IsDevelopment()) return NotFound();
        return Ok(new { message = "Bạn có quyền staff/admin.", me.Role });
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

    // Lưu ý: với record, attribute validate phải đặt trên THAM SỐ constructor (không dùng [property: ...]).
    public sealed record DevTokenRequest(
        [Required(ErrorMessage = "Vui lòng nhập email.")]
        [EmailAddress(ErrorMessage = "Email không đúng định dạng.")]
        string Email,
        [Required(ErrorMessage = "Vui lòng nhập mật khẩu.")]
        string Password);

    public sealed record DevTokenResponse(string IdToken, string Uid, int ExpiresInSeconds);

    private sealed record FirebaseSignInResponse(string IdToken, string LocalId, string ExpiresIn);

    private sealed record SeedData(List<Category> Categories, List<SeedVoucher> Vouchers, List<SeedAccount> Accounts);

    private sealed record SeedVoucher(
        string Code, string Description, DiscountType DiscountType, int DiscountValue,
        int? MaxDiscount, int MinOrderAmount, int ValidDays, int? UsageLimit, int? PerUserLimit);

    private sealed record SeedAccount(
        string Email, string Password, string FullName, UserRole Role,
        string? StudentCode = null, string? Phone = null);
}
