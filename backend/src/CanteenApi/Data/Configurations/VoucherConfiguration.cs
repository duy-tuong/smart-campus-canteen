using CanteenApi.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace CanteenApi.Data.Configurations;

public class VoucherConfiguration : IEntityTypeConfiguration<Voucher>
{
    public void Configure(EntityTypeBuilder<Voucher> e)
    {
        e.ToTable("Vouchers", t =>
        {
            t.HasCheckConstraint("CK_Vouchers_DiscountValue", "[DiscountValue] > 0");
            t.HasCheckConstraint("CK_Vouchers_Percent", "[DiscountType] <> 'Percent' OR [DiscountValue] <= 100");
            t.HasCheckConstraint("CK_Vouchers_MaxDiscount", "[MaxDiscount] IS NULL OR [MaxDiscount] > 0");
            t.HasCheckConstraint("CK_Vouchers_MinOrderAmount", "[MinOrderAmount] >= 0");
            t.HasCheckConstraint("CK_Vouchers_Period", "[EndAt] > [StartAt]");
            t.HasCheckConstraint("CK_Vouchers_UsageLimit", "[UsageLimit] IS NULL OR [UsageLimit] > 0");
            t.HasCheckConstraint("CK_Vouchers_PerUserLimit", "[PerUserLimit] IS NULL OR [PerUserLimit] > 0");
            t.HasCheckConstraint("CK_Vouchers_UsedCount", "[UsedCount] >= 0 AND ([UsageLimit] IS NULL OR [UsedCount] <= [UsageLimit])");
        });

        e.Property(x => x.Code).HasMaxLength(30).IsUnicode(false).IsRequired();
        e.Property(x => x.Description).HasMaxLength(300).IsRequired();
        e.Property(x => x.DiscountType).HasConversion<string>().HasMaxLength(20).IsUnicode(false);
        e.Property(x => x.RowVersion).IsRowVersion();
        e.Property(x => x.CreatedAt).HasDefaultValueSql("SYSUTCDATETIME()");
        e.Property(x => x.UpdatedAt).HasDefaultValueSql("SYSUTCDATETIME()");

        e.HasIndex(x => x.Code).IsUnique();
        e.HasIndex(x => new { x.IsActive, x.StartAt, x.EndAt });
    }
}
