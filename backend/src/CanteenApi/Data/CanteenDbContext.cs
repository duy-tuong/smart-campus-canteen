using CanteenApi.Models;
using Microsoft.EntityFrameworkCore;

namespace CanteenApi.Data;

/// <summary>
/// EF Core DbContext cho SQL Server — nguồn dữ liệu chính của hệ thống.
///
/// Quan hệ:
///   Categories 1 ── n Foods
///   Users      1 ── n Orders 1 ── n OrderItems n ── 1 Foods (FoodId có thể null)
/// </summary>
public class CanteenDbContext(DbContextOptions<CanteenDbContext> options) : DbContext(options)
{
    public DbSet<Category> Categories => Set<Category>();
    public DbSet<Food> Foods => Set<Food>();
    public DbSet<AppUser> Users => Set<AppUser>();
    public DbSet<Order> Orders => Set<Order>();
    public DbSet<OrderItem> OrderItems => Set<OrderItem>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Category>(e =>
        {
            e.ToTable("Categories");
            e.Property(x => x.Name).HasMaxLength(100).IsRequired();
            e.Property(x => x.Icon).HasMaxLength(50);
            e.HasIndex(x => x.Name).IsUnique();
        });

        modelBuilder.Entity<Food>(e =>
        {
            e.ToTable("Foods", t =>
            {
                t.HasCheckConstraint("CK_Foods_Price", "[Price] > 0");
                t.HasCheckConstraint("CK_Foods_PrepTime", "[PrepTimeMinutes] >= 0");
            });
            e.Property(x => x.Name).HasMaxLength(150).IsRequired();
            e.Property(x => x.Description).HasMaxLength(500);
            e.Property(x => x.ImageUrl).HasMaxLength(300);
            e.Property(x => x.CreatedAt).HasDefaultValueSql("SYSUTCDATETIME()");
            e.Property(x => x.UpdatedAt).HasDefaultValueSql("SYSUTCDATETIME()");

            // Không cho xóa danh mục khi còn món bên trong.
            e.HasOne(x => x.Category)
             .WithMany(c => c.Foods)
             .HasForeignKey(x => x.CategoryId)
             .OnDelete(DeleteBehavior.Restrict);

            e.HasIndex(x => x.CategoryId);
        });

        modelBuilder.Entity<AppUser>(e =>
        {
            e.ToTable("Users");
            e.Property(x => x.Id).HasMaxLength(128); // Firebase uid
            e.Property(x => x.Email).HasMaxLength(256).IsRequired();
            e.Property(x => x.FullName).HasMaxLength(100).IsRequired();
            e.Property(x => x.StudentId).HasMaxLength(20);
            e.Property(x => x.Role).HasMaxLength(20).HasDefaultValue("student");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("SYSUTCDATETIME()");
            e.HasIndex(x => x.Email).IsUnique();
        });

        modelBuilder.Entity<Order>(e =>
        {
            e.ToTable("Orders", t =>
            {
                t.HasCheckConstraint("CK_Orders_TotalAmount", "[TotalAmount] >= 0");
                t.HasCheckConstraint("CK_Orders_TotalItems", "[TotalItems] > 0");
            });
            e.Property(x => x.Id).HasMaxLength(36);
            e.Property(x => x.UserId).HasMaxLength(128);
            e.Property(x => x.PickupCode).HasMaxLength(10).IsRequired();
            e.Property(x => x.Status).HasConversion<string>().HasMaxLength(20); // lưu chữ, dễ đọc trong SSMS
            e.Property(x => x.Note).HasMaxLength(300);
            e.Property(x => x.CreatedAt).HasDefaultValueSql("SYSUTCDATETIME()");
            e.Property(x => x.UpdatedAt).HasDefaultValueSql("SYSUTCDATETIME()");

            e.HasOne(x => x.User)
             .WithMany(u => u.Orders)
             .HasForeignKey(x => x.UserId)
             .OnDelete(DeleteBehavior.Restrict);

            e.HasIndex(x => new { x.UserId, x.CreatedAt });
            e.HasIndex(x => x.Status);
        });

        modelBuilder.Entity<OrderItem>(e =>
        {
            e.ToTable("OrderItems", t =>
            {
                t.HasCheckConstraint("CK_OrderItems_Quantity", "[Quantity] > 0");
                t.HasCheckConstraint("CK_OrderItems_UnitPrice", "[UnitPrice] >= 0");
            });
            e.Property(x => x.OrderId).HasMaxLength(36);
            e.Property(x => x.FoodName).HasMaxLength(150).IsRequired();

            // Xóa đơn → xóa luôn chi tiết.
            e.HasOne(x => x.Order)
             .WithMany(o => o.Items)
             .HasForeignKey(x => x.OrderId)
             .OnDelete(DeleteBehavior.Cascade);

            // Xóa món khỏi menu → chi tiết đơn cũ giữ nguyên, FoodId = NULL.
            e.HasOne(x => x.Food)
             .WithMany()
             .HasForeignKey(x => x.FoodId)
             .OnDelete(DeleteBehavior.SetNull);
        });
    }
}
