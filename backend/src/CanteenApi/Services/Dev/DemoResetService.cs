using CanteenApi.Common;
using CanteenApi.Data;
using CanteenApi.Models;
using CanteenApi.Services.Reviews;
using Microsoft.EntityFrameworkCore;

namespace CanteenApi.Services.Dev;

/// <summary>Một voucher mẫu trong SeedData/menu.json (hạn dùng tính từ ngày nạp).</summary>
public sealed record SeedVoucher(
    string Code, string Description, DiscountType DiscountType, int DiscountValue,
    int? MaxDiscount, int MinOrderAmount, int ValidDays, int? UsageLimit, int? PerUserLimit);

public sealed record DemoResetResult(
    int OrdersDeleted, int ReviewsDeleted, int NotificationsDeleted,
    int FoodsRestored, int FoodsHidden, int CategoriesRestored, int CategoriesHidden,
    int VouchersRefreshed, int VouchersRemoved);

/// <summary>
/// Đưa dữ liệu về trạng thái "sẵn sàng demo" mà KHÔNG xóa trắng database (giữ tài khoản, yêu thích và
/// dữ liệu lịch sử do <see cref="HistorySeeder"/> sinh):
///  - Xóa mọi đơn "thật" (tạo khi chạy thử app, không mang mã hist-…) cùng đánh giá của chúng → không còn đơn dở
///    trên bảng đơn, sinh viên không bị chặn bởi giới hạn số đơn đang xử lý, mã nhận món hôm nay đánh lại từ 001.
///  - Xóa toàn bộ thông báo.
///  - Thực đơn về đúng menu.json (so khớp theo TÊN): giá, mô tả, số suất, ảnh, đang bán; món / danh mục thêm khi
///    tập dượt bị ẩn (xóa mềm). Nhóm tùy chọn không được khôi phục.
///  - Voucher mẫu được gia hạn tính từ hôm nay và bật lại; voucher tạo thêm bị xóa (hoặc tắt nếu còn đơn dùng).
/// Dọn bản sao trên Firebase RTDB do nơi gọi đảm nhận (service chỉ làm việc với SQL Server).
/// </summary>
public sealed class DemoResetService(
    CanteenDbContext db, ReviewService reviews, IFileStorage files, TimeProvider clock, ILogger<DemoResetService> logger)
{
    public async Task<DemoResetResult> ResetAsync(
        IReadOnlyList<Category> seedMenu, IReadOnlyList<SeedVoucher> seedVouchers, CancellationToken ct)
    {
        var realOrders = db.Orders.Where(o =>
            o.ClientRequestId == null || !o.ClientRequestId.StartsWith(HistorySeeder.HistoryPrefix));
        var replacedImages = new List<string>();

        await using var tx = await db.Database.BeginTransactionAsync(ct);

        // 1. Đơn chạy thử + đánh giá của chúng + thông báo.
        var reviewsDeleted = await db.Reviews.Where(r => realOrders.Any(o => o.Id == r.OrderId)).ExecuteDeleteAsync(ct);
        var ordersDeleted = await realOrders.ExecuteDeleteAsync(ct); // cascade: món, tùy chọn, lịch sử, thanh toán
        var notificationsDeleted = await db.Notifications.ExecuteDeleteAsync(ct);

        // 2. Danh mục & món theo menu.json.
        var (categoriesRestored, categoriesHidden, foodsRestored, foodsHidden) = await RestoreMenuAsync(seedMenu, replacedImages, ct);

        // 3. Voucher.
        var (vouchersRefreshed, vouchersRemoved) = await RestoreVouchersAsync(seedVouchers, ct);

        await db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);

        foreach (var path in replacedImages) files.Delete(path); // chỉ xóa được ảnh upload, giữ ảnh mẫu
        await reviews.RecalculateAllFoodRatingsAsync(ct);         // điểm sao chỉ còn từ đánh giá lịch sử

        var result = new DemoResetResult(ordersDeleted, reviewsDeleted, notificationsDeleted,
            foodsRestored, foodsHidden, categoriesRestored, categoriesHidden, vouchersRefreshed, vouchersRemoved);
        logger.LogInformation("Demo reset {@Result}", result);
        return result;
    }

    private async Task<(int, int, int, int)> RestoreMenuAsync(
        IReadOnlyList<Category> seedMenu, List<string> replacedImages, CancellationToken ct)
    {
        var categories = await db.Categories.Include(c => c.Foods).OrderBy(c => c.Id).ToListAsync(ct);
        int categoriesRestored = 0, categoriesHidden = 0, foodsRestored = 0, foodsHidden = 0;

        // Mỗi tên trong menu.json chỉ khôi phục MỘT bản ghi (ưu tiên bản đang hiển thị, rồi bản cũ nhất);
        // bản trùng tên còn lại bị ẩn để không hiện hai món cùng tên.
        var seedCategories = seedMenu.ToDictionary(c => c.Name, StringComparer.OrdinalIgnoreCase);
        var restoredCategory = new Dictionary<string, Category>(StringComparer.OrdinalIgnoreCase);
        foreach (var category in categories.OrderBy(c => c.IsDeleted).ThenBy(c => c.Id))
        {
            if (seedCategories.TryGetValue(category.Name, out var seed) && restoredCategory.TryAdd(seed.Name, category))
            {
                category.Description = seed.Description;
                category.Icon = seed.Icon;
                category.SortOrder = seed.SortOrder;
                category.IsActive = true;
                category.IsDeleted = false;
                categoriesRestored++;
            }
            else if (!category.IsDeleted)
            {
                category.IsDeleted = true;
                category.IsActive = false;
                categoriesHidden++;
            }
        }

        var seedFoods = seedMenu.SelectMany(c => c.Foods.Select(f => (CategoryName: c.Name, Food: f)))
            .ToDictionary(x => x.Food.Name, StringComparer.OrdinalIgnoreCase);
        var restoredFoods = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var food in categories.SelectMany(c => c.Foods).OrderBy(f => f.IsDeleted).ThenBy(f => f.Id))
        {
            if (seedFoods.TryGetValue(food.Name, out var seed)
                && restoredCategory.TryGetValue(seed.CategoryName, out var target)
                && restoredFoods.Add(seed.Food.Name))
            {
                food.CategoryId = target.Id;
                food.Description = seed.Food.Description;
                food.Price = seed.Food.Price;
                food.PrepTimeMinutes = seed.Food.PrepTimeMinutes;
                food.DailyLimit = seed.Food.DailyLimit;
                food.IsAvailable = true;
                food.IsDeleted = false;
                if (seed.Food.ImageUrl is { } image && food.ImageUrl != image)
                {
                    if (food.ImageUrl is not null) replacedImages.Add(food.ImageUrl);
                    food.ImageUrl = image;
                }
                foodsRestored++;
            }
            else if (!food.IsDeleted)
            {
                food.IsDeleted = true;
                food.IsAvailable = false;
                foodsHidden++;
            }
        }
        return (categoriesRestored, categoriesHidden, foodsRestored, foodsHidden);
    }

    private async Task<(int Refreshed, int Removed)> RestoreVouchersAsync(IReadOnlyList<SeedVoucher> seedVouchers, CancellationToken ct)
    {
        var todayStartUtc = VietnamTime.DayRangeUtc(DateOnly.FromDateTime(VietnamTime.Now(clock))).StartUtc;
        var seeds = seedVouchers.ToDictionary(v => v.Code, StringComparer.OrdinalIgnoreCase);
        // Số đơn chưa hủy còn lại theo voucher (sau khi đã xóa đơn chạy thử) → UsedCount đúng thực tế.
        var usage = await db.Orders.Where(o => o.VoucherId != null)
            .GroupBy(o => o.VoucherId!.Value)
            .Select(g => new { Id = g.Key, Total = g.Count(), Active = g.Count(o => o.Status != OrderStatus.Cancelled) })
            .ToDictionaryAsync(x => x.Id, ct);

        int refreshed = 0, removed = 0;
        foreach (var voucher in await db.Vouchers.ToListAsync(ct))
        {
            usage.TryGetValue(voucher.Id, out var used);
            if (seeds.TryGetValue(voucher.Code, out var seed))
            {
                voucher.Description = seed.Description;
                voucher.DiscountType = seed.DiscountType;
                voucher.DiscountValue = seed.DiscountValue;
                voucher.MaxDiscount = seed.MaxDiscount;
                voucher.MinOrderAmount = seed.MinOrderAmount;
                voucher.UsageLimit = seed.UsageLimit;
                voucher.PerUserLimit = seed.PerUserLimit;
                voucher.StartAt = todayStartUtc;
                voucher.EndAt = todayStartUtc.AddDays(seed.ValidDays);
                voucher.IsActive = true;
                voucher.UsedCount = used?.Active ?? 0;
                refreshed++;
            }
            else if (voucher.Code == HistorySeeder.HistoryVoucherCode)
            {
                // Voucher "khai trường" của dữ liệu lịch sử: giữ nguyên (đã hết hạn theo kịch bản).
            }
            else if (used is null)
            {
                db.Vouchers.Remove(voucher);
                removed++;
            }
            else
            {
                voucher.IsActive = false; // còn đơn lịch sử tham chiếu → chỉ tắt
                voucher.UsedCount = used.Active;
                removed++;
            }
        }
        return (refreshed, removed);
    }
}
