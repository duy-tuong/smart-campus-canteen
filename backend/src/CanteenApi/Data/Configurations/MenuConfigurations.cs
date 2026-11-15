using CanteenApi.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace CanteenApi.Data.Configurations;

public class CategoryConfiguration : IEntityTypeConfiguration<Category>
{
    public void Configure(EntityTypeBuilder<Category> e)
    {
        e.ToTable("Categories", t => t.HasCheckConstraint("CK_Categories_SortOrder", "[SortOrder] >= 0"));

        e.Property(x => x.Name).HasMaxLength(100).IsRequired();
        e.Property(x => x.Description).HasMaxLength(300);
        e.Property(x => x.Icon).HasMaxLength(50).IsUnicode(false).IsRequired();
        e.Property(x => x.CreatedAt).HasDefaultValueSql("SYSUTCDATETIME()");
        e.Property(x => x.UpdatedAt).HasDefaultValueSql("SYSUTCDATETIME()");

        // Tên danh mục duy nhất trong số các danh mục CHƯA bị xóa mềm.
        e.HasIndex(x => x.Name).IsUnique().HasFilter("[IsDeleted] = 0");
        e.HasIndex(x => new { x.IsDeleted, x.IsActive, x.SortOrder });
    }
}

public class FoodConfiguration : IEntityTypeConfiguration<Food>
{
    public void Configure(EntityTypeBuilder<Food> e)
    {
        e.ToTable("Foods", t =>
        {
            t.HasCheckConstraint("CK_Foods_Price", "[Price] > 0");
            t.HasCheckConstraint("CK_Foods_PrepTime", "[PrepTimeMinutes] BETWEEN 0 AND 180");
            t.HasCheckConstraint("CK_Foods_DailyLimit", "[DailyLimit] IS NULL OR [DailyLimit] > 0");
            t.HasCheckConstraint("CK_Foods_AverageRating", "[AverageRating] BETWEEN 0 AND 5");
            t.HasCheckConstraint("CK_Foods_RatingCount", "[RatingCount] >= 0");
        });

        e.Property(x => x.Name).HasMaxLength(150).IsRequired();
        e.Property(x => x.Description).HasMaxLength(500).IsRequired();
        e.Property(x => x.ImageUrl).HasMaxLength(500);
        e.Property(x => x.AverageRating).HasPrecision(3, 2);
        e.Property(x => x.RowVersion).IsRowVersion();
        e.Property(x => x.CreatedAt).HasDefaultValueSql("SYSUTCDATETIME()");
        e.Property(x => x.UpdatedAt).HasDefaultValueSql("SYSUTCDATETIME()");

        // Không cho xóa danh mục khi còn món bên trong.
        e.HasOne(x => x.Category)
         .WithMany(c => c.Foods)
         .HasForeignKey(x => x.CategoryId)
         .OnDelete(DeleteBehavior.Restrict);

        // Không trùng tên món trong cùng một danh mục (chỉ xét món chưa xóa).
        e.HasIndex(x => new { x.CategoryId, x.Name }).IsUnique().HasFilter("[IsDeleted] = 0");
        e.HasIndex(x => new { x.IsDeleted, x.IsAvailable });
    }
}

public class FoodOptionGroupConfiguration : IEntityTypeConfiguration<FoodOptionGroup>
{
    public void Configure(EntityTypeBuilder<FoodOptionGroup> e)
    {
        e.ToTable("FoodOptionGroups", t =>
        {
            t.HasCheckConstraint("CK_FoodOptionGroups_MinSelect", "[MinSelect] >= 0");
            t.HasCheckConstraint("CK_FoodOptionGroups_MaxSelect", "[MaxSelect] >= 1 AND [MaxSelect] >= [MinSelect]");
            // Nhóm bắt buộc thì phải chọn ít nhất 1.
            t.HasCheckConstraint("CK_FoodOptionGroups_Required", "[IsRequired] = 0 OR [MinSelect] >= 1");
        });

        e.Property(x => x.Name).HasMaxLength(50).IsRequired();

        e.HasOne(x => x.Food)
         .WithMany(f => f.OptionGroups)
         .HasForeignKey(x => x.FoodId)
         .OnDelete(DeleteBehavior.Cascade);

        e.HasIndex(x => new { x.FoodId, x.Name }).IsUnique();
    }
}

public class FoodOptionConfiguration : IEntityTypeConfiguration<FoodOption>
{
    public void Configure(EntityTypeBuilder<FoodOption> e)
    {
        e.ToTable("FoodOptions", t => t.HasCheckConstraint("CK_FoodOptions_ExtraPrice", "[ExtraPrice] >= 0"));

        e.Property(x => x.Name).HasMaxLength(100).IsRequired();

        e.HasOne(x => x.Group)
         .WithMany(g => g.Options)
         .HasForeignKey(x => x.GroupId)
         .OnDelete(DeleteBehavior.Cascade);

        e.HasIndex(x => new { x.GroupId, x.Name }).IsUnique();
    }
}

public class FavoriteConfiguration : IEntityTypeConfiguration<Favorite>
{
    public void Configure(EntityTypeBuilder<Favorite> e)
    {
        e.ToTable("Favorites");

        // Khóa chính kép: mỗi người chỉ yêu thích một món một lần.
        e.HasKey(x => new { x.UserId, x.FoodId });
        e.Property(x => x.UserId).HasMaxLength(128);
        e.Property(x => x.CreatedAt).HasDefaultValueSql("SYSUTCDATETIME()");

        e.HasOne(x => x.User)
         .WithMany(u => u.Favorites)
         .HasForeignKey(x => x.UserId)
         .OnDelete(DeleteBehavior.Cascade);

        e.HasOne(x => x.Food)
         .WithMany()
         .HasForeignKey(x => x.FoodId)
         .OnDelete(DeleteBehavior.Cascade);

        e.HasIndex(x => x.FoodId);
    }
}
