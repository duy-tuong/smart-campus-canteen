using CanteenApi.Common;
using CanteenApi.Data;
using CanteenApi.Dtos.Menu;
using CanteenApi.Models;
using Microsoft.EntityFrameworkCore;

namespace CanteenApi.Services;

/// <summary>Nghiệp vụ danh mục món ăn.</summary>
public sealed class CategoryService(CanteenDbContext db, ILogger<CategoryService> logger)
{
    /// <summary>
    /// Danh sách danh mục, sắp theo SortOrder.
    /// <paramref name="includeInactive"/> = true (chỉ staff/admin) để thấy cả danh mục đang ẩn.
    /// </summary>
    public async Task<IReadOnlyList<CategoryDto>> ListAsync(bool includeInactive, CancellationToken ct) =>
        await Visible(includeInactive)
            .OrderBy(c => c.SortOrder).ThenBy(c => c.Name)
            .Select(ToDto)
            .ToListAsync(ct);

    public async Task<CategoryDto> GetAsync(int id, bool includeInactive, CancellationToken ct) =>
        await Visible(includeInactive).Where(c => c.Id == id).Select(ToDto).FirstOrDefaultAsync(ct)
        ?? throw new NotFoundException("Không tìm thấy danh mục.");

    public async Task<CategoryDto> CreateAsync(SaveCategoryRequest request, CancellationToken ct)
    {
        var name = request.Name.Trim();
        await EnsureNameAvailableAsync(name, excludeId: null, ct);

        var category = new Category
        {
            Name = name,
            Description = NormalizeOptional(request.Description),
            Icon = request.Icon,
            SortOrder = request.SortOrder,
            IsActive = request.IsActive ?? true,
        };
        db.Categories.Add(category);
        await db.SaveChangesAsync(ct);

        logger.LogInformation("Created category {Id} {Name}", category.Id, category.Name);
        return await GetAsync(category.Id, includeInactive: true, ct);
    }

    public async Task<CategoryDto> UpdateAsync(int id, SaveCategoryRequest request, CancellationToken ct)
    {
        var category = await FindAsync(id, ct);
        var name = request.Name.Trim();
        if (!string.Equals(name, category.Name, StringComparison.Ordinal))
            await EnsureNameAvailableAsync(name, excludeId: id, ct);

        category.Name = name;
        category.Description = NormalizeOptional(request.Description);
        category.Icon = request.Icon;
        category.SortOrder = request.SortOrder;
        category.IsActive = request.IsActive ?? category.IsActive;
        await db.SaveChangesAsync(ct);

        return await GetAsync(id, includeInactive: true, ct);
    }

    /// <summary>Cập nhật thứ tự hiển thị của nhiều danh mục trong một transaction.</summary>
    public async Task<IReadOnlyList<CategoryDto>> ReorderAsync(ReorderCategoriesRequest request, CancellationToken ct)
    {
        var ids = request.Items.Select(i => i.Id).ToList();
        if (ids.Distinct().Count() != ids.Count)
            throw new BadRequestException(ErrorCodes.ValidationError, "Danh sách sắp xếp có Id bị trùng.");

        var categories = await db.Categories.Where(c => ids.Contains(c.Id) && !c.IsDeleted).ToListAsync(ct);
        var missing = ids.Except(categories.Select(c => c.Id)).ToList();
        if (missing.Count > 0)
            throw new NotFoundException($"Không tìm thấy danh mục: {string.Join(", ", missing)}.");

        foreach (var item in request.Items)
            categories.First(c => c.Id == item.Id).SortOrder = item.SortOrder;

        await db.SaveChangesAsync(ct);
        return await ListAsync(includeInactive: true, ct);
    }

    /// <summary>
    /// Xóa mềm danh mục. Không cho xóa khi còn món (chưa xóa) bên trong:
    /// staff phải chuyển hoặc xóa các món trước, tránh "mồ côi" món ăn.
    /// </summary>
    public async Task DeleteAsync(int id, CancellationToken ct)
    {
        var category = await FindAsync(id, ct);

        var foodCount = await db.Foods.CountAsync(f => f.CategoryId == id && !f.IsDeleted, ct);
        if (foodCount > 0)
            throw new ConflictException(ErrorCodes.CategoryNotEmpty,
                $"Danh mục còn {foodCount} món. Hãy chuyển hoặc xóa các món trước khi xóa danh mục.");

        category.IsDeleted = true;
        category.IsActive = false;
        await db.SaveChangesAsync(ct);
        logger.LogInformation("Soft-deleted category {Id}", id);
    }

    // ---------------------------------------------------------------

    private IQueryable<Category> Visible(bool includeInactive) =>
        db.Categories.AsNoTracking().Where(c => !c.IsDeleted && (includeInactive || c.IsActive));

    private static readonly System.Linq.Expressions.Expression<Func<Category, CategoryDto>> ToDto = c =>
        new CategoryDto(c.Id, c.Name, c.Description, c.Icon, c.SortOrder, c.IsActive,
                        c.Foods.Count(f => !f.IsDeleted));

    private async Task<Category> FindAsync(int id, CancellationToken ct) =>
        await db.Categories.FirstOrDefaultAsync(c => c.Id == id && !c.IsDeleted, ct)
        ?? throw new NotFoundException("Không tìm thấy danh mục.");

    private async Task EnsureNameAvailableAsync(string name, int? excludeId, CancellationToken ct)
    {
        var taken = await db.Categories.AnyAsync(c =>
            !c.IsDeleted && c.Id != excludeId &&
            EF.Functions.Collate(c.Name, SearchCollation.AccentInsensitive) == name, ct);

        if (taken) throw new ConflictException(ErrorCodes.CategoryNameTaken, $"Danh mục \"{name}\" đã tồn tại.");
    }

    private static string? NormalizeOptional(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
