using CanteenApi.Common;
using CanteenApi.Data;
using CanteenApi.Dtos.Menu;
using CanteenApi.Models;
using Microsoft.EntityFrameworkCore;

namespace CanteenApi.Services;

/// <summary>
/// Nghiệp vụ món ăn: xem/lọc/tìm (sinh viên), thêm/sửa/xóa + tùy chọn + ảnh (staff/admin), yêu thích.
///
/// Quy tắc hiển thị:
///  - Sinh viên: món chưa xóa, thuộc danh mục đang hiện; tùy chọn tạm hết bị ẩn.
///  - Staff/admin (includeInactive): thấy cả món thuộc danh mục đang ẩn và mọi tùy chọn.
///  - Món "tạm hết" vẫn hiển thị (kèm cờ isSoldOut) để sinh viên biết căn-tin có món này.
/// </summary>
public sealed class FoodService(
    CanteenDbContext db,
    IFileStorage files,
    IPublicUrlBuilder urls,
    TimeProvider clock,
    ILogger<FoodService> logger)
{
    private const int MaxOptionGroups = 10;

    // ============================ Đọc ============================

    public async Task<PagedResult<FoodSummaryDto>> ListAsync(
        FoodQuery query, string uid, bool isStaff, CancellationToken ct)
    {
        var includeInactive = isStaff && query.IncludeInactive;
        var foods = VisibleFoods(includeInactive);

        if (query.CategoryId is { } categoryId) foods = foods.Where(f => f.CategoryId == categoryId);
        if (query.MinPrice is { } min) foods = foods.Where(f => f.Price >= min);
        if (query.MaxPrice is { } max) foods = foods.Where(f => f.Price <= max);

        if (!string.IsNullOrWhiteSpace(query.Q))
        {
            var term = query.Q.Trim();
            foods = foods.Where(f =>
                EF.Functions.Collate(f.Name, SearchCollation.AccentInsensitive).Contains(term) ||
                EF.Functions.Collate(f.Description, SearchCollation.AccentInsensitive).Contains(term));
        }

        var rows = ProjectRows(foods, uid);

        if (query.AvailableOnly)
            rows = rows.Where(r => r.IsAvailable && (r.DailyLimit == null || r.SoldToday < r.DailyLimit));

        rows = query.Sort switch
        {
            "popular" => rows.OrderByDescending(r => r.Sold30Days).ThenBy(r => r.Name),
            "price_asc" => rows.OrderBy(r => r.Price).ThenBy(r => r.Name),
            "price_desc" => rows.OrderByDescending(r => r.Price).ThenBy(r => r.Name),
            "rating" => rows.OrderByDescending(r => r.AverageRating).ThenByDescending(r => r.RatingCount).ThenBy(r => r.Name),
            "newest" => rows.OrderByDescending(r => r.CreatedAt).ThenBy(r => r.Id),
            _ => rows.OrderBy(r => r.Name).ThenBy(r => r.Id),
        };

        var page = await rows.ToPagedResultAsync(query, ct);
        return new PagedResult<FoodSummaryDto>(
            page.Items.Select(ToSummary).ToList(), page.Page, page.PageSize, page.TotalCount);
    }

    public async Task<FoodDetailDto> GetDetailAsync(int id, string uid, bool isStaff, CancellationToken ct)
    {
        var row = await ProjectRows(VisibleFoods(includeInactive: isStaff).Where(f => f.Id == id), uid)
            .FirstOrDefaultAsync(ct)
            ?? throw new NotFoundException("Không tìm thấy món ăn.");

        var food = await db.Foods.AsNoTracking()
            .Where(f => f.Id == id)
            .Select(f => new { f.Description, f.RowVersion, f.UpdatedAt })
            .FirstAsync(ct);

        var groups = await db.FoodOptionGroups.AsNoTracking()
            .Where(g => g.FoodId == id)
            .OrderBy(g => g.SortOrder).ThenBy(g => g.Id)
            .Select(g => new FoodOptionGroupDto(
                g.Id, g.Name, g.IsRequired, g.MinSelect, g.MaxSelect, g.SortOrder,
                g.Options
                    .Where(o => isStaff || o.IsAvailable)
                    .OrderBy(o => o.SortOrder).ThenBy(o => o.Id)
                    .Select(o => new FoodOptionDto(o.Id, o.Name, o.ExtraPrice, o.IsAvailable, o.SortOrder))
                    .ToList()))
            .ToListAsync(ct);

        var summary = ToSummary(row);
        return new FoodDetailDto(
            summary.Id, summary.Name, food.Description, summary.Price, summary.ImageUrl,
            summary.CategoryId, summary.CategoryName, summary.PrepTimeMinutes, row.DailyLimit,
            summary.AverageRating, summary.RatingCount, summary.IsAvailable, summary.RemainingToday,
            summary.IsSoldOut, summary.IsFavorite,
            groups.Where(g => g.Options.Count > 0).ToList(),
            Convert.ToBase64String(food.RowVersion), row.CreatedAt, food.UpdatedAt);
    }

    // ============================ Ghi (staff/admin) ============================

    public async Task<int> CreateAsync(CreateFoodRequest request, CancellationToken ct)
    {
        await EnsureCategoryUsableAsync(request.CategoryId, ct);
        var name = request.Name.Trim();
        await EnsureNameAvailableAsync(request.CategoryId, name, excludeId: null, ct);

        var groups = request.OptionGroups ?? [];
        ValidateOptionGroups(groups);

        var food = new Food
        {
            CategoryId = request.CategoryId,
            Name = name,
            Description = request.Description.Trim(),
            Price = request.Price,
            PrepTimeMinutes = request.PrepTimeMinutes,
            DailyLimit = request.DailyLimit,
            IsAvailable = request.IsAvailable ?? true,
            OptionGroups = BuildOptionGroups(groups),
        };
        db.Foods.Add(food);
        await db.SaveChangesAsync(ct);

        logger.LogInformation("Created food {Id} {Name}", food.Id, food.Name);
        return food.Id;
    }

    /// <summary>
    /// Sửa thông tin món. Bắt buộc gửi rowVersion đã đọc: nếu trong lúc đó người khác đã sửa,
    /// SQL Server phát hiện qua cột rowversion và trả 409 CONCURRENCY_CONFLICT (không ghi đè mất dữ liệu).
    /// </summary>
    public async Task UpdateAsync(int id, UpdateFoodRequest request, CancellationToken ct)
    {
        var food = await FindAsync(id, ct);
        ApplyExpectedRowVersion(food, request.RowVersion);

        var name = request.Name.Trim();
        if (request.CategoryId != food.CategoryId) await EnsureCategoryUsableAsync(request.CategoryId, ct);
        if (request.CategoryId != food.CategoryId || !string.Equals(name, food.Name, StringComparison.Ordinal))
            await EnsureNameAvailableAsync(request.CategoryId, name, excludeId: id, ct);

        food.CategoryId = request.CategoryId;
        food.Name = name;
        food.Description = request.Description.Trim();
        food.Price = request.Price;
        food.PrepTimeMinutes = request.PrepTimeMinutes;
        food.DailyLimit = request.DailyLimit;
        food.IsAvailable = request.IsAvailable!.Value;

        await db.SaveChangesAsync(ct);
    }

    /// <summary>
    /// Thay toàn bộ cây tùy chọn của món trong một transaction.
    /// Hóa đơn cũ không bị ảnh hưởng vì OrderItemOptions đã lưu bản chụp tên + giá.
    /// Đồng thời "chạm" vào món (UpdatedAt) để rowVersion đổi → form sửa món đang mở ở máy khác sẽ bị báo xung đột.
    /// </summary>
    public async Task ReplaceOptionGroupsAsync(int id, ReplaceOptionGroupsRequest request, CancellationToken ct)
    {
        ValidateOptionGroups(request.Groups);
        var food = await FindAsync(id, ct);

        await using var tx = await db.Database.BeginTransactionAsync(ct);

        // Xóa trước rồi mới thêm (2 lần SaveChanges) để không vướng UNIQUE(FoodId, Name) khi giữ lại tên nhóm cũ.
        await db.FoodOptionGroups.Where(g => g.FoodId == id).ExecuteDeleteAsync(ct); // cascade xóa FoodOptions

        foreach (var group in BuildOptionGroups(request.Groups))
        {
            group.FoodId = id;
            db.FoodOptionGroups.Add(group);
        }
        db.Entry(food).Property(f => f.UpdatedAt).IsModified = true; // ApplyTimestamps gán giờ mới
        await db.SaveChangesAsync(ct);

        await tx.CommitAsync(ct);
    }

    /// <summary>Bật/tắt "hết món" (thao tác nhanh của staff trong giờ cao điểm).</summary>
    public async Task SetAvailabilityAsync(int id, bool isAvailable, CancellationToken ct)
    {
        var food = await FindAsync(id, ct);
        food.IsAvailable = isAvailable;
        await db.SaveChangesAsync(ct);
    }

    public async Task UpdateImageAsync(int id, IFormFile file, CancellationToken ct)
    {
        var food = await FindAsync(id, ct);
        var oldPath = food.ImageUrl;

        food.ImageUrl = await files.SaveImageAsync(file, UploadFolder.Foods, FileStorageService.MaxFoodImageBytes, ct);
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch
        {
            files.Delete(food.ImageUrl); // lưu DB thất bại → không để lại file mồ côi
            throw;
        }

        files.Delete(oldPath); // chỉ xóa được file trong /uploads, ảnh seed /images được giữ nguyên
    }

    /// <summary>
    /// Xóa mềm: món không còn hiển thị/đặt được nhưng vẫn giữ trong database
    /// để hóa đơn, đánh giá và thống kê doanh thu cũ vẫn đúng. Gỡ khỏi danh sách yêu thích.
    /// </summary>
    public async Task DeleteAsync(int id, CancellationToken ct)
    {
        var food = await FindAsync(id, ct);

        await using var tx = await db.Database.BeginTransactionAsync(ct);
        food.IsDeleted = true;
        food.IsAvailable = false;
        await db.SaveChangesAsync(ct);
        await db.Favorites.Where(f => f.FoodId == id).ExecuteDeleteAsync(ct);
        await tx.CommitAsync(ct);

        logger.LogInformation("Soft-deleted food {Id}", id);
    }

    // ============================ Yêu thích ============================

    /// <summary>Thêm vào yêu thích (idempotent: đã có thì bỏ qua).</summary>
    public async Task AddFavoriteAsync(string uid, int foodId, CancellationToken ct)
    {
        if (!await VisibleFoods(includeInactive: false).AnyAsync(f => f.Id == foodId, ct))
            throw new NotFoundException("Không tìm thấy món ăn.");

        if (await db.Favorites.AnyAsync(f => f.UserId == uid && f.FoodId == foodId, ct)) return;

        db.Favorites.Add(new Favorite { UserId = uid, FoodId = foodId, CreatedAt = clock.GetUtcNow().UtcDateTime });
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (ex.InnerException is Microsoft.Data.SqlClient.SqlException { Number: 2627 })
        {
            // Vi phạm khóa chính (UserId, FoodId): request song song đã thêm trước → kết quả vẫn đúng.
        }
    }

    public Task RemoveFavoriteAsync(string uid, int foodId, CancellationToken ct) =>
        db.Favorites.Where(f => f.UserId == uid && f.FoodId == foodId).ExecuteDeleteAsync(ct);

    /// <summary>Món yêu thích của tôi (chỉ món còn hiển thị), mới thêm trước.</summary>
    public async Task<PagedResult<FoodSummaryDto>> ListFavoritesAsync(string uid, PageQuery query, CancellationToken ct)
    {
        var foods = VisibleFoods(includeInactive: false)
            .Where(f => db.Favorites.Any(x => x.UserId == uid && x.FoodId == f.Id));

        var rows = ProjectRows(foods, uid)
            .OrderByDescending(r => db.Favorites
                .Where(x => x.UserId == uid && x.FoodId == r.Id)
                .Select(x => x.CreatedAt).FirstOrDefault());

        var page = await rows.ToPagedResultAsync(query, ct);
        return new PagedResult<FoodSummaryDto>(
            page.Items.Select(ToSummary).ToList(), page.Page, page.PageSize, page.TotalCount);
    }

    // ============================ Truy vấn dùng chung ============================

    /// <summary>Món còn hiển thị (chưa xóa, danh mục chưa xóa; với sinh viên: danh mục đang hiện).</summary>
    private IQueryable<Food> VisibleFoods(bool includeInactive) =>
        db.Foods.AsNoTracking().Where(f =>
            !f.IsDeleted && !f.Category!.IsDeleted && (includeInactive || f.Category.IsActive));

    /// <summary>
    /// Chiếu món sang FoodRow, tính trong CÙNG một câu SQL:
    ///  - SoldToday: tổng số lượng đã đặt hôm nay (giờ Việt Nam), bỏ qua đơn bị hủy
    ///  - Sold30Days: dùng cho sắp xếp "bán chạy"
    ///  - HasOptions, IsFavorite (theo người đang xem)
    /// </summary>
    private IQueryable<FoodRow> ProjectRows(IQueryable<Food> foods, string uid)
    {
        var (todayStart, todayEnd) = VietnamTime.TodayRangeUtc(clock);
        var since30 = todayStart.AddDays(-29);

        var counted = db.OrderItems.Where(i => i.Order!.Status != OrderStatus.Cancelled);

        return foods.Select(f => new FoodRow
        {
            Id = f.Id,
            Name = f.Name,
            Price = f.Price,
            ImageUrl = f.ImageUrl,
            CategoryId = f.CategoryId,
            CategoryName = f.Category!.Name,
            PrepTimeMinutes = f.PrepTimeMinutes,
            DailyLimit = f.DailyLimit,
            AverageRating = f.AverageRating,
            RatingCount = f.RatingCount,
            IsAvailable = f.IsAvailable,
            CreatedAt = f.CreatedAt,
            SoldToday = counted
                .Where(i => i.FoodId == f.Id && i.Order!.CreatedAt >= todayStart && i.Order.CreatedAt < todayEnd)
                .Sum(i => (int?)i.Quantity) ?? 0,
            Sold30Days = counted
                .Where(i => i.FoodId == f.Id && i.Order!.CreatedAt >= since30)
                .Sum(i => (int?)i.Quantity) ?? 0,
            HasOptions = f.OptionGroups.Any(),
            IsFavorite = db.Favorites.Any(x => x.UserId == uid && x.FoodId == f.Id),
        });
    }

    private FoodSummaryDto ToSummary(FoodRow r)
    {
        int? remaining = r.DailyLimit is { } limit ? Math.Max(0, limit - r.SoldToday) : null;
        var soldOut = !r.IsAvailable || remaining == 0;
        return new FoodSummaryDto(
            r.Id, r.Name, r.Price, urls.Build(r.ImageUrl), r.CategoryId, r.CategoryName,
            r.PrepTimeMinutes, r.AverageRating, r.RatingCount, r.IsAvailable, remaining, soldOut,
            r.HasOptions, r.IsFavorite);
    }

    // ============================ Kiểm tra nghiệp vụ ============================

    private async Task<Food> FindAsync(int id, CancellationToken ct) =>
        await db.Foods.FirstOrDefaultAsync(f => f.Id == id && !f.IsDeleted, ct)
        ?? throw new NotFoundException("Không tìm thấy món ăn.");

    private async Task EnsureCategoryUsableAsync(int categoryId, CancellationToken ct)
    {
        if (!await db.Categories.AnyAsync(c => c.Id == categoryId && !c.IsDeleted, ct))
            throw new BusinessRuleException(ErrorCodes.InvalidCategory, "Danh mục không tồn tại hoặc đã bị xóa.");
    }

    private async Task EnsureNameAvailableAsync(int categoryId, string name, int? excludeId, CancellationToken ct)
    {
        var taken = await db.Foods.AnyAsync(f =>
            f.CategoryId == categoryId && !f.IsDeleted && f.Id != excludeId &&
            EF.Functions.Collate(f.Name, SearchCollation.AccentInsensitive) == name, ct);

        if (taken)
            throw new ConflictException(ErrorCodes.FoodNameTaken, $"Danh mục này đã có món \"{name}\".");
    }

    private void ApplyExpectedRowVersion(Food food, string rowVersion)
    {
        byte[] expected;
        try
        {
            expected = Convert.FromBase64String(rowVersion);
        }
        catch (FormatException)
        {
            throw new BadRequestException(ErrorCodes.ValidationError, "rowVersion không hợp lệ.");
        }

        // EF so sánh giá trị "gốc" này với cột rowversion trong WHERE của câu UPDATE.
        db.Entry(food).Property(f => f.RowVersion).OriginalValue = expected;
    }

    /// <summary>
    /// Quy tắc tùy chọn (lỗi → 422 INVALID_OPTIONS):
    ///  - tên nhóm không trùng trong một món; tên tùy chọn không trùng trong một nhóm
    ///  - nhóm bắt buộc ⇔ MinSelect ≥ 1
    ///  - MinSelect ≤ MaxSelect ≤ số tùy chọn của nhóm
    /// </summary>
    private static void ValidateOptionGroups(IReadOnlyList<SaveOptionGroupRequest> groups)
    {
        var errors = new List<string>();
        if (groups.Count > MaxOptionGroups) errors.Add($"Mỗi món tối đa {MaxOptionGroups} nhóm tùy chọn.");

        var duplicateGroups = groups.GroupBy(g => g.Name.Trim(), StringComparer.OrdinalIgnoreCase)
            .Where(g => g.Count() > 1).Select(g => g.Key).ToList();
        if (duplicateGroups.Count > 0) errors.Add($"Trùng tên nhóm: {string.Join(", ", duplicateGroups)}.");

        foreach (var g in groups)
        {
            var label = $"Nhóm \"{g.Name.Trim()}\"";
            if (g.IsRequired && g.MinSelect < 1)
                errors.Add($"{label}: nhóm bắt buộc phải có số lựa chọn tối thiểu ≥ 1.");
            if (!g.IsRequired && g.MinSelect > 0)
                errors.Add($"{label}: nhóm không bắt buộc phải có số lựa chọn tối thiểu = 0.");
            if (g.MinSelect > g.MaxSelect)
                errors.Add($"{label}: số lựa chọn tối thiểu lớn hơn tối đa.");
            if (g.MaxSelect > g.Options.Count)
                errors.Add($"{label}: số lựa chọn tối đa ({g.MaxSelect}) lớn hơn số tùy chọn ({g.Options.Count}).");

            var duplicateOptions = g.Options.GroupBy(o => o.Name.Trim(), StringComparer.OrdinalIgnoreCase)
                .Where(o => o.Count() > 1).Select(o => o.Key).ToList();
            if (duplicateOptions.Count > 0)
                errors.Add($"{label}: trùng tên tùy chọn {string.Join(", ", duplicateOptions)}.");
        }

        if (errors.Count > 0)
            throw new BusinessRuleException(ErrorCodes.InvalidOptions, string.Join(" ", errors));
    }

    private static List<FoodOptionGroup> BuildOptionGroups(IReadOnlyList<SaveOptionGroupRequest> groups) =>
        groups.Select((g, gi) => new FoodOptionGroup
        {
            Name = g.Name.Trim(),
            IsRequired = g.IsRequired,
            MinSelect = g.MinSelect,
            MaxSelect = g.MaxSelect,
            SortOrder = g.SortOrder ?? gi + 1,
            Options = g.Options.Select((o, oi) => new FoodOption
            {
                Name = o.Name.Trim(),
                ExtraPrice = o.ExtraPrice,
                IsAvailable = o.IsAvailable ?? true,
                SortOrder = o.SortOrder ?? oi + 1,
            }).ToList(),
        }).ToList();

    /// <summary>Kết quả chiếu trung gian (EF dịch được toàn bộ sang SQL, kể cả lọc/sắp xếp trên các cột tính toán).</summary>
    private sealed class FoodRow
    {
        public int Id { get; init; }
        public string Name { get; init; } = string.Empty;
        public int Price { get; init; }
        public string? ImageUrl { get; init; }
        public int CategoryId { get; init; }
        public string CategoryName { get; init; } = string.Empty;
        public int PrepTimeMinutes { get; init; }
        public int? DailyLimit { get; init; }
        public decimal AverageRating { get; init; }
        public int RatingCount { get; init; }
        public bool IsAvailable { get; init; }
        public DateTime CreatedAt { get; init; }
        public int SoldToday { get; init; }
        public int Sold30Days { get; init; }
        public bool HasOptions { get; init; }
        public bool IsFavorite { get; init; }
    }
}
