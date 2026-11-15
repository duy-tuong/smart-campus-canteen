using CanteenApi.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace CanteenApi.Data.Configurations;

public class UserConfiguration : IEntityTypeConfiguration<AppUser>
{
    public void Configure(EntityTypeBuilder<AppUser> e)
    {
        e.ToTable("Users", t =>
        {
            t.HasCheckConstraint("CK_Users_Email", "[Email] LIKE '%_@_%._%'");
            t.HasCheckConstraint("CK_Users_Phone", "[Phone] IS NULL OR [Phone] NOT LIKE '%[^0-9+]%'");
        });

        e.HasKey(x => x.Id);
        e.Property(x => x.Id).HasMaxLength(128); // Firebase uid
        e.Property(x => x.Email).HasMaxLength(256).IsUnicode(false).IsRequired();
        e.Property(x => x.FullName).HasMaxLength(100).IsRequired();
        e.Property(x => x.StudentCode).HasMaxLength(20).IsUnicode(false);
        e.Property(x => x.Phone).HasMaxLength(15).IsUnicode(false);
        e.Property(x => x.AvatarUrl).HasMaxLength(500);
        e.Property(x => x.Role).HasConversion<string>().HasMaxLength(20).IsUnicode(false);
        e.Property(x => x.CreatedAt).HasDefaultValueSql("SYSUTCDATETIME()");
        e.Property(x => x.UpdatedAt).HasDefaultValueSql("SYSUTCDATETIME()");

        e.HasIndex(x => x.Email).IsUnique();
        // Unique có lọc: nhiều staff/admin được phép để trống mã sinh viên.
        e.HasIndex(x => x.StudentCode).IsUnique().HasFilter("[StudentCode] IS NOT NULL");
        e.HasIndex(x => x.Role);
    }
}
