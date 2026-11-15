using CanteenApi.Models;
using Microsoft.EntityFrameworkCore;

namespace CanteenApi.Data;

/// <summary>
/// EF Core DbContext cho SQL Server — nguồn dữ liệu chính của hệ thống (14 bảng).
///
///   Người dùng : Users
///   Thực đơn   : Categories 1─n Foods 1─n FoodOptionGroups 1─n FoodOptions
///                Users n─n Foods (qua Favorites)
///   Khuyến mãi : Vouchers 1─n Orders
///   Đơn hàng   : Users 1─n Orders 1─n OrderItems 1─n OrderItemOptions
///                Orders 1─n OrderStatusHistory, Orders 1─n Payments
///   Tương tác  : Reviews (User, Food, Order), Notifications (User)
///
/// Cấu hình chi tiết (kiểu cột, CHECK, UNIQUE, FK, index) nằm trong thư mục Data/Configurations.
/// </summary>
public class CanteenDbContext(DbContextOptions<CanteenDbContext> options, TimeProvider? clock = null) : DbContext(options)
{
    /// <summary>
    /// Nguồn thời gian DUY NHẤT của hệ thống (qua DI). CreatedAt/UpdatedAt phải cùng đồng hồ với nghiệp vụ
    /// ("hôm nay", số suất đã bán...), nếu không đơn vừa tạo có thể bị tính sang ngày khác.
    /// </summary>
    private readonly TimeProvider _clock = clock ?? TimeProvider.System;

    public DbSet<AppUser> Users => Set<AppUser>();
    public DbSet<Category> Categories => Set<Category>();
    public DbSet<Food> Foods => Set<Food>();
    public DbSet<FoodOptionGroup> FoodOptionGroups => Set<FoodOptionGroup>();
    public DbSet<FoodOption> FoodOptions => Set<FoodOption>();
    public DbSet<Favorite> Favorites => Set<Favorite>();
    public DbSet<Voucher> Vouchers => Set<Voucher>();
    public DbSet<Order> Orders => Set<Order>();
    public DbSet<OrderItem> OrderItems => Set<OrderItem>();
    public DbSet<OrderItemOption> OrderItemOptions => Set<OrderItemOption>();
    public DbSet<OrderStatusHistory> OrderStatusHistory => Set<OrderStatusHistory>();
    public DbSet<Payment> Payments => Set<Payment>();
    public DbSet<Review> Reviews => Set<Review>();
    public DbSet<Notification> Notifications => Set<Notification>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(CanteenDbContext).Assembly);
    }

    protected override void ConfigureConventions(ModelConfigurationBuilder configurationBuilder)
    {
        // Mọi DateTime lưu dạng datetime2 (chính xác hơn datetime cũ), giá trị luôn là UTC.
        // datetime2 không lưu múi giờ → khi đọc ra gắn Kind=Utc để JSON trả về dạng "...Z"
        // (nếu không, app sẽ hiểu nhầm là giờ địa phương và lệch 7 tiếng).
        configurationBuilder.Properties<DateTime>()
            .HaveColumnType("datetime2(3)")
            .HaveConversion<UtcDateTimeConverter>();
    }

    /// <summary>Ghi: đổi giờ địa phương (nếu có) sang UTC. Đọc: gắn Kind=Utc.</summary>
    internal sealed class UtcDateTimeConverter() : Microsoft.EntityFrameworkCore.Storage.ValueConversion.ValueConverter<DateTime, DateTime>(
        v => v.Kind == DateTimeKind.Local ? v.ToUniversalTime() : v,
        v => DateTime.SpecifyKind(v, DateTimeKind.Utc));

    public override int SaveChanges(bool acceptAllChangesOnSuccess)
    {
        ApplyTimestamps();
        return base.SaveChanges(acceptAllChangesOnSuccess);
    }

    public override Task<int> SaveChangesAsync(bool acceptAllChangesOnSuccess, CancellationToken cancellationToken = default)
    {
        ApplyTimestamps();
        return base.SaveChangesAsync(acceptAllChangesOnSuccess, cancellationToken);
    }

    /// <summary>Tự gán CreatedAt/UpdatedAt (UTC) cho các entity <see cref="IAuditable"/>.</summary>
    private void ApplyTimestamps()
    {
        var now = _clock.GetUtcNow().UtcDateTime;
        foreach (var entry in ChangeTracker.Entries<IAuditable>())
        {
            if (entry.State == EntityState.Added)
            {
                entry.Entity.CreatedAt = now;
                entry.Entity.UpdatedAt = now;
            }
            else if (entry.State == EntityState.Modified)
            {
                entry.Property(x => x.CreatedAt).IsModified = false;
                entry.Entity.UpdatedAt = now;
            }
        }
    }
}
