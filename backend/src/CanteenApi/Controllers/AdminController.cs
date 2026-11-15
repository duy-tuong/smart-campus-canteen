using System.Text.Json;
using CanteenApi.Auth;
using CanteenApi.Models;
using CanteenApi.Services;
using FirebaseAdmin.Auth;
using Microsoft.AspNetCore.Mvc;

namespace CanteenApi.Controllers;

/// <summary>
/// Công cụ khởi tạo dữ liệu cho môi trường phát triển (nạp menu mẫu, cấp quyền staff).
/// Chỉ hoạt động khi ASPNETCORE_ENVIRONMENT=Development; môi trường khác trả 404.
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class AdminController(
    FirebaseDbService db,
    IWebHostEnvironment env,
    ILogger<AdminController> logger) : ControllerBase
{
    /// <summary>
    /// POST /api/admin/seed — nạp danh mục và món ăn từ SeedData/menu.json lên Realtime Database
    /// (ghi đè các node categories và foods).
    /// </summary>
    [HttpPost("seed")]
    public async Task<IActionResult> Seed(CancellationToken ct)
    {
        if (!env.IsDevelopment()) return NotFound();

        var path = Path.Combine(AppContext.BaseDirectory, "SeedData", "menu.json");
        await using var stream = System.IO.File.OpenRead(path);
        var seed = await JsonSerializer.DeserializeAsync<SeedMenu>(stream, FirebaseDbService.JsonOptions, ct)
                   ?? throw new InvalidOperationException("menu.json rỗng hoặc sai định dạng.");

        // Lưu dạng map {id: object} để Flutter/Backend truy cập trực tiếp foods/{id}.
        await db.SetAsync("categories", seed.Categories.ToDictionary(c => c.Id), ct);
        await db.SetAsync("foods", seed.Foods.ToDictionary(f => f.Id), ct);

        logger.LogInformation("Seeded {Categories} categories, {Foods} foods", seed.Categories.Count, seed.Foods.Count);
        return Ok(new { categories = seed.Categories.Count, foods = seed.Foods.Count });
    }

    /// <summary>
    /// POST /api/admin/staff?email=... — gán custom claim role=staff cho tài khoản đã đăng ký.
    /// Người dùng cần đăng nhập lại (hoặc getIdToken(true)) để token mới có quyền.
    /// </summary>
    [HttpPost("staff")]
    public async Task<IActionResult> GrantStaff([FromQuery] string email)
    {
        if (!env.IsDevelopment()) return NotFound();

        try
        {
            var user = await FirebaseAuth.DefaultInstance.GetUserByEmailAsync(email);
            await FirebaseAuth.DefaultInstance.SetCustomUserClaimsAsync(
                user.Uid, new Dictionary<string, object> { ["role"] = Roles.Staff });
            return Ok(new { user.Uid, email, role = Roles.Staff });
        }
        catch (FirebaseAuthException ex) when (ex.AuthErrorCode == AuthErrorCode.UserNotFound)
        {
            return NotFound(new { message = $"Không tìm thấy tài khoản {email}. Hãy đăng ký trong app trước." });
        }
    }

    private sealed record SeedMenu(List<Category> Categories, List<Food> Foods);
}
