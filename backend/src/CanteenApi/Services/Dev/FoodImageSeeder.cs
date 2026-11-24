using CanteenApi.Data;
using Microsoft.EntityFrameworkCore;

namespace CanteenApi.Services.Dev;

/// <summary>Kết quả gắn ảnh mẫu.</summary>
/// <param name="Updated">Số món vừa được gắn / đổi ảnh.</param>
/// <param name="Skipped">Số món giữ nguyên (đã đúng ảnh, hoặc đã có ảnh riêng mà không yêu cầu ghi đè).</param>
/// <param name="MissingFiles">Đường dẫn ảnh khai báo nhưng không có file trong wwwroot.</param>
/// <param name="UnknownFoods">Tên món khai báo nhưng không có trong database.</param>
public sealed record FoodImageSeedResult(
    int Updated, int Skipped, IReadOnlyList<string> MissingFiles, IReadOnlyList<string> UnknownFoods);

/// <summary>
/// Gắn ảnh mẫu cho món theo TÊN món — dùng cho database đã có dữ liệu (không phải reset, giữ nguyên lịch sử đơn).
/// Ảnh mẫu nằm trong wwwroot/images (commit cùng source, xem wwwroot/images/CREDITS.md), khác với ảnh do
/// nhân viên upload (wwwroot/uploads). Mặc định KHÔNG ghi đè ảnh nhân viên đã tự upload.
/// </summary>
public sealed class FoodImageSeeder(
    CanteenDbContext db, IWebHostEnvironment env, IFileStorage files, ILogger<FoodImageSeeder> logger)
{
    public const string ImagesPrefix = "/images/";

    /// <param name="imageByFoodName">Tên món → đường dẫn ảnh dạng "/images/com-ga-xoi-mo.jpg".</param>
    /// <param name="overwrite">true: thay cả ảnh đã có (ảnh upload cũ bị xóa khỏi wwwroot/uploads).</param>
    public async Task<FoodImageSeedResult> ApplyAsync(
        IReadOnlyDictionary<string, string> imageByFoodName, bool overwrite, CancellationToken ct)
    {
        var imagesRoot = Path.GetFullPath(Path.Combine(env.WebRootPath, "images")) + Path.DirectorySeparatorChar;
        // Lấy cả món đã xóa mềm: đơn cũ vẫn hiển thị ảnh của món.
        var foods = await db.Foods.IgnoreQueryFilters().ToListAsync(ct);

        var missing = new List<string>();
        var unknown = new List<string>();
        var replaced = new List<string>();
        int updated = 0, skipped = 0;

        foreach (var (name, url) in imageByFoodName)
        {
            if (!url.StartsWith(ImagesPrefix, StringComparison.Ordinal))
                throw new ArgumentException($"Ảnh mẫu phải nằm trong {ImagesPrefix}: {url}", nameof(imageByFoodName));

            // Chặn path traversal ("/images/../appsettings.json").
            var fullPath = Path.GetFullPath(Path.Combine(env.WebRootPath, url.TrimStart('/')));
            if (!fullPath.StartsWith(imagesRoot, StringComparison.OrdinalIgnoreCase))
                throw new ArgumentException($"Đường dẫn ảnh không hợp lệ: {url}", nameof(imageByFoodName));
            if (!File.Exists(fullPath))
            {
                missing.Add(url);
                continue;
            }

            var matches = foods.Where(f => string.Equals(f.Name, name, StringComparison.OrdinalIgnoreCase)).ToList();
            if (matches.Count == 0) unknown.Add(name);

            foreach (var food in matches)
            {
                if (food.ImageUrl == url || (food.ImageUrl is not null && !overwrite))
                {
                    skipped++;
                    continue;
                }
                if (food.ImageUrl is not null) replaced.Add(food.ImageUrl);
                food.ImageUrl = url;
                updated++;
            }
        }

        await db.SaveChangesAsync(ct);
        foreach (var old in replaced) files.Delete(old); // chỉ xóa được file trong /uploads; ảnh mẫu được giữ

        logger.LogInformation("Seeded food images: {Updated} updated, {Skipped} skipped, {Missing} missing files",
            updated, skipped, missing.Count);
        return new FoodImageSeedResult(updated, skipped, missing, unknown);
    }
}
