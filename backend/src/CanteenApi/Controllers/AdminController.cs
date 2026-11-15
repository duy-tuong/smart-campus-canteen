using System.Text.Json;
using CanteenApi.Auth;
using CanteenApi.Data;
using CanteenApi.Models;
using CanteenApi.Services;
using FirebaseAdmin.Auth;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace CanteenApi.Controllers;

/// <summary>
/// Công cụ khởi tạo dữ liệu cho môi trường phát triển (nạp menu mẫu, cấp quyền staff).
/// Chỉ hoạt động khi ASPNETCORE_ENVIRONMENT=Development; môi trường khác trả 404.
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class AdminController(
    CanteenDbContext db,
    IWebHostEnvironment env,
    ILogger<AdminController> logger) : ControllerBase
{
    /// <summary>
    /// POST /api/admin/seed[?reset=true] — nạp danh mục và món ăn từ SeedData/menu.json vào SQL Server.
    /// Nếu đã có dữ liệu thì trả 409, trừ khi truyền reset=true (xóa menu cũ rồi nạp lại).
    /// </summary>
    [HttpPost("seed")]
    public async Task<IActionResult> Seed([FromQuery] bool reset, CancellationToken ct)
    {
        if (!env.IsDevelopment()) return NotFound();

        if (await db.Categories.AnyAsync(ct))
        {
            if (!reset)
                return Conflict(new { message = "Menu đã có dữ liệu. Gọi lại với ?reset=true để nạp lại." });

            // Xóa món trước (FK Restrict từ Foods → Categories). OrderItems.FoodId tự về NULL.
            await db.Foods.ExecuteDeleteAsync(ct);
            await db.Categories.ExecuteDeleteAsync(ct);

            // Đặt lại bộ đếm IDENTITY để Id món/danh mục bắt đầu lại từ 1.
            await db.Database.ExecuteSqlRawAsync(
                "DBCC CHECKIDENT ('Foods', RESEED, 0); DBCC CHECKIDENT ('Categories', RESEED, 0);", ct);
        }

        var path = Path.Combine(AppContext.BaseDirectory, "SeedData", "menu.json");
        await using var stream = System.IO.File.OpenRead(path);
        var seed = await JsonSerializer.DeserializeAsync<SeedMenu>(stream, FirebaseDbService.JsonOptions, ct)
                   ?? throw new InvalidOperationException("menu.json rỗng hoặc sai định dạng.");

        db.Categories.AddRange(seed.Categories); // EF tự chèn cả Foods lồng bên trong
        await db.SaveChangesAsync(ct);

        var foodCount = seed.Categories.Sum(c => c.Foods.Count);
        logger.LogInformation("Seeded {Categories} categories, {Foods} foods", seed.Categories.Count, foodCount);
        return Ok(new { categories = seed.Categories.Count, foods = foodCount });
    }

    /// <summary>
    /// POST /api/admin/staff?email=... — gán custom claim role=staff cho tài khoản đã đăng ký
    /// và cập nhật cột Role trong bảng Users.
    /// Người dùng cần đăng nhập lại (hoặc getIdToken(true)) để token mới có quyền.
    /// </summary>
    [HttpPost("staff")]
    public async Task<IActionResult> GrantStaff([FromQuery] string email, CancellationToken ct)
    {
        if (!env.IsDevelopment()) return NotFound();

        try
        {
            var user = await FirebaseAuth.DefaultInstance.GetUserByEmailAsync(email, ct);
            await FirebaseAuth.DefaultInstance.SetCustomUserClaimsAsync(
                user.Uid, new Dictionary<string, object> { ["role"] = Roles.Staff }, ct);

            await db.Users.Where(u => u.Id == user.Uid)
                .ExecuteUpdateAsync(s => s.SetProperty(u => u.Role, Roles.Staff), ct);

            return Ok(new { user.Uid, email, role = Roles.Staff });
        }
        catch (FirebaseAuthException ex) when (ex.AuthErrorCode == AuthErrorCode.UserNotFound)
        {
            return NotFound(new { message = $"Không tìm thấy tài khoản {email}. Hãy đăng ký trong app trước." });
        }
    }

    private sealed record SeedMenu(List<Category> Categories);
}
