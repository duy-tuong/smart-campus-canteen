using CanteenApi.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace CanteenApi.Data.Configurations;

public class ReviewConfiguration : IEntityTypeConfiguration<Review>
{
    public void Configure(EntityTypeBuilder<Review> e)
    {
        e.ToTable("Reviews", t =>
        {
            t.HasCheckConstraint("CK_Reviews_Rating", "[Rating] BETWEEN 1 AND 5");
            // Ẩn đánh giá phải nêu lý do (tác giả được xem lý do).
            t.HasCheckConstraint("CK_Reviews_HiddenReason", "[IsHidden] = 0 OR [HiddenReason] IS NOT NULL");
            // Phản hồi của căn-tin: nội dung, thời điểm, người trả lời đi cùng nhau.
            t.HasCheckConstraint("CK_Reviews_Reply",
                "([StaffReply] IS NULL AND [RepliedAt] IS NULL AND [RepliedByUserId] IS NULL) OR " +
                "([StaffReply] IS NOT NULL AND [RepliedAt] IS NOT NULL AND [RepliedByUserId] IS NOT NULL)");
        });

        e.Property(x => x.UserId).HasMaxLength(128);
        e.Property(x => x.OrderId).HasMaxLength(36);
        e.Property(x => x.Comment).HasMaxLength(500);
        e.Property(x => x.HiddenReason).HasMaxLength(300);
        e.Property(x => x.StaffReply).HasMaxLength(500);
        e.Property(x => x.RepliedByUserId).HasMaxLength(128);
        e.Property(x => x.CreatedAt).HasDefaultValueSql("SYSUTCDATETIME()");
        e.Property(x => x.UpdatedAt).HasDefaultValueSql("SYSUTCDATETIME()");

        e.HasOne(x => x.Order)
         .WithMany(o => o.Reviews)
         .HasForeignKey(x => x.OrderId)
         .OnDelete(DeleteBehavior.Cascade);

        e.HasOne(x => x.User)
         .WithMany(u => u.Reviews)
         .HasForeignKey(x => x.UserId)
         .OnDelete(DeleteBehavior.Restrict);

        // Món dùng xóa mềm nên không bao giờ bị xóa vật lý khi còn đánh giá.
        e.HasOne(x => x.Food)
         .WithMany(f => f.Reviews)
         .HasForeignKey(x => x.FoodId)
         .OnDelete(DeleteBehavior.Restrict);

        e.HasOne(x => x.RepliedByUser)
         .WithMany()
         .HasForeignKey(x => x.RepliedByUserId)
         .OnDelete(DeleteBehavior.Restrict);

        // Mỗi món trong một đơn chỉ được đánh giá một lần.
        e.HasIndex(x => new { x.OrderId, x.FoodId }).IsUnique();
        // Danh sách đánh giá công khai của một món (lọc bỏ đánh giá bị ẩn, mới nhất trước).
        e.HasIndex(x => new { x.FoodId, x.IsHidden, x.CreatedAt });
        e.HasIndex(x => x.UserId);
    }
}

public class NotificationConfiguration : IEntityTypeConfiguration<Notification>
{
    public void Configure(EntityTypeBuilder<Notification> e)
    {
        e.ToTable("Notifications");

        e.Property(x => x.UserId).HasMaxLength(128);
        e.Property(x => x.Title).HasMaxLength(150).IsRequired();
        e.Property(x => x.Body).HasMaxLength(500).IsRequired();
        e.Property(x => x.Type).HasConversion<string>().HasMaxLength(20).IsUnicode(false);
        e.Property(x => x.RefId).HasMaxLength(64).IsUnicode(false);
        e.Property(x => x.CreatedAt).HasDefaultValueSql("SYSUTCDATETIME()");

        e.HasOne(x => x.User)
         .WithMany(u => u.Notifications)
         .HasForeignKey(x => x.UserId)
         .OnDelete(DeleteBehavior.Cascade);

        // Danh sách thông báo của tôi + đếm chưa đọc.
        e.HasIndex(x => new { x.UserId, x.IsRead, x.CreatedAt });
    }
}
