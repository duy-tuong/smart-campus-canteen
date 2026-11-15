using CanteenApi.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace CanteenApi.Data.Configurations;

public class OrderConfiguration : IEntityTypeConfiguration<Order>
{
    public void Configure(EntityTypeBuilder<Order> e)
    {
        e.ToTable("Orders", t =>
        {
            t.HasCheckConstraint("CK_Orders_Subtotal", "[Subtotal] > 0");
            t.HasCheckConstraint("CK_Orders_Discount", "[DiscountAmount] >= 0 AND [DiscountAmount] <= [Subtotal]");
            t.HasCheckConstraint("CK_Orders_Total", "[TotalAmount] = [Subtotal] - [DiscountAmount]");
            // Đơn bị hủy phải có lý do.
            t.HasCheckConstraint("CK_Orders_CancelReason", "[Status] <> 'Cancelled' OR [CancelReason] IS NOT NULL");
            // Có VoucherId thì phải lưu lại mã voucher.
            t.HasCheckConstraint("CK_Orders_VoucherCode", "[VoucherId] IS NULL OR [VoucherCode] IS NOT NULL");
            t.HasCheckConstraint("CK_Orders_PaymentStatus",
                "[PaymentStatus] IN ('Pending', 'Paid', 'Refunded', 'Failed')");
            // Đã thanh toán (hoặc đã hoàn tiền) thì phải có thời điểm thanh toán.
            t.HasCheckConstraint("CK_Orders_PaidAt", "[PaymentStatus] NOT IN ('Paid', 'Refunded') OR [PaidAt] IS NOT NULL");
        });

        e.Property(x => x.Id).HasMaxLength(36);
        e.Property(x => x.PickupCode).HasMaxLength(10).IsUnicode(false).IsRequired();
        e.Property(x => x.ClientRequestId).HasMaxLength(64).IsUnicode(false);
        e.Property(x => x.PaymentStatus).HasConversion<string>().HasMaxLength(20).IsUnicode(false);
        e.Property(x => x.UserId).HasMaxLength(128);
        e.Property(x => x.VoucherCode).HasMaxLength(30).IsUnicode(false);
        e.Property(x => x.Status).HasConversion<string>().HasMaxLength(20).IsUnicode(false);
        e.Property(x => x.PaymentMethod).HasConversion<string>().HasMaxLength(20).IsUnicode(false);
        e.Property(x => x.Note).HasMaxLength(300);
        e.Property(x => x.CancelReason).HasMaxLength(300);
        e.Property(x => x.RowVersion).IsRowVersion();
        e.Property(x => x.CreatedAt).HasDefaultValueSql("SYSUTCDATETIME()");
        e.Property(x => x.UpdatedAt).HasDefaultValueSql("SYSUTCDATETIME()");

        // Không cho xóa người dùng/voucher đã phát sinh đơn hàng (dữ liệu kế toán).
        e.HasOne(x => x.User)
         .WithMany(u => u.Orders)
         .HasForeignKey(x => x.UserId)
         .OnDelete(DeleteBehavior.Restrict);

        e.HasOne(x => x.Voucher)
         .WithMany(v => v.Orders)
         .HasForeignKey(x => x.VoucherId)
         .OnDelete(DeleteBehavior.Restrict);

        e.HasIndex(x => new { x.UserId, x.CreatedAt });   // "Đơn của tôi"
        e.HasIndex(x => new { x.Status, x.CreatedAt });   // Bảng đơn của staff
        e.HasIndex(x => x.CreatedAt);                     // Thống kê doanh thu theo ngày
        e.HasIndex(x => x.VoucherId);

        // Mã nhận món không trùng trong cùng một ngày (giờ Việt Nam).
        e.HasIndex(x => new { x.PickupDate, x.PickupCode }).IsUnique();

        // Idempotency: một người dùng không thể tạo hai đơn với cùng một Idempotency-Key.
        e.HasIndex(x => new { x.UserId, x.ClientRequestId }).IsUnique().HasFilter("[ClientRequestId] IS NOT NULL");
    }
}

public class OrderItemConfiguration : IEntityTypeConfiguration<OrderItem>
{
    public void Configure(EntityTypeBuilder<OrderItem> e)
    {
        e.ToTable("OrderItems", t =>
        {
            t.HasCheckConstraint("CK_OrderItems_Quantity", "[Quantity] BETWEEN 1 AND 50");
            t.HasCheckConstraint("CK_OrderItems_UnitPrice", "[UnitPrice] > 0");
            t.HasCheckConstraint("CK_OrderItems_OptionsPrice", "[OptionsPrice] >= 0");
            t.HasCheckConstraint("CK_OrderItems_LineTotal", "[LineTotal] = ([UnitPrice] + [OptionsPrice]) * [Quantity]");
        });

        e.Property(x => x.OrderId).HasMaxLength(36);
        e.Property(x => x.FoodName).HasMaxLength(150).IsRequired();
        e.Property(x => x.Note).HasMaxLength(200);

        // Xóa đơn → xóa luôn chi tiết.
        e.HasOne(x => x.Order)
         .WithMany(o => o.Items)
         .HasForeignKey(x => x.OrderId)
         .OnDelete(DeleteBehavior.Cascade);

        // Xóa món khỏi menu → chi tiết đơn cũ giữ nguyên tên/giá, FoodId = NULL.
        e.HasOne(x => x.Food)
         .WithMany()
         .HasForeignKey(x => x.FoodId)
         .OnDelete(DeleteBehavior.SetNull);

        e.HasIndex(x => x.FoodId); // Thống kê món bán chạy
    }
}

public class OrderItemOptionConfiguration : IEntityTypeConfiguration<OrderItemOption>
{
    public void Configure(EntityTypeBuilder<OrderItemOption> e)
    {
        e.ToTable("OrderItemOptions", t => t.HasCheckConstraint("CK_OrderItemOptions_ExtraPrice", "[ExtraPrice] >= 0"));

        e.Property(x => x.GroupName).HasMaxLength(50).IsRequired();
        e.Property(x => x.OptionName).HasMaxLength(100).IsRequired();

        e.HasOne(x => x.OrderItem)
         .WithMany(i => i.Options)
         .HasForeignKey(x => x.OrderItemId)
         .OnDelete(DeleteBehavior.Cascade);
    }
}

public class OrderStatusHistoryConfiguration : IEntityTypeConfiguration<OrderStatusHistory>
{
    public void Configure(EntityTypeBuilder<OrderStatusHistory> e)
    {
        e.ToTable("OrderStatusHistory", t =>
            t.HasCheckConstraint("CK_OrderStatusHistory_Change", "[FromStatus] IS NULL OR [FromStatus] <> [ToStatus]"));

        e.Property(x => x.OrderId).HasMaxLength(36);
        e.Property(x => x.FromStatus).HasConversion<string>().HasMaxLength(20).IsUnicode(false);
        e.Property(x => x.ToStatus).HasConversion<string>().HasMaxLength(20).IsUnicode(false);
        e.Property(x => x.ChangedByUserId).HasMaxLength(128);
        e.Property(x => x.Note).HasMaxLength(300);
        e.Property(x => x.ChangedAt).HasDefaultValueSql("SYSUTCDATETIME()");

        e.HasOne(x => x.Order)
         .WithMany(o => o.StatusHistory)
         .HasForeignKey(x => x.OrderId)
         .OnDelete(DeleteBehavior.Cascade);

        // Giữ dấu vết người thao tác: không cho xóa user còn nhật ký.
        e.HasOne(x => x.ChangedByUser)
         .WithMany()
         .HasForeignKey(x => x.ChangedByUserId)
         .OnDelete(DeleteBehavior.Restrict);

        e.HasIndex(x => new { x.OrderId, x.ChangedAt });
    }
}

public class PaymentConfiguration : IEntityTypeConfiguration<Payment>
{
    public void Configure(EntityTypeBuilder<Payment> e)
    {
        e.ToTable("Payments", t =>
        {
            t.HasCheckConstraint("CK_Payments_Amount", "[Amount] >= 0");
            // Đã thanh toán thì phải có thời điểm thanh toán.
            t.HasCheckConstraint("CK_Payments_PaidAt", "[Status] <> 'Paid' OR [PaidAt] IS NOT NULL");
            t.HasCheckConstraint("CK_Payments_ProviderOrderCode", "[ProviderOrderCode] IS NULL OR [ProviderOrderCode] > 0");
            // Thông tin payOS chỉ có với thanh toán chuyển khoản.
            t.HasCheckConstraint("CK_Payments_ProviderMethod", "[ProviderOrderCode] IS NULL OR [Method] = 'BankTransfer'");
        });

        e.Property(x => x.OrderId).HasMaxLength(36);
        e.Property(x => x.Method).HasConversion<string>().HasMaxLength(20).IsUnicode(false);
        e.Property(x => x.Status).HasConversion<string>().HasMaxLength(20).IsUnicode(false);
        e.Property(x => x.TransactionRef).HasMaxLength(100).IsUnicode(false);
        e.Property(x => x.PaymentLinkId).HasMaxLength(64).IsUnicode(false);
        e.Property(x => x.CheckoutUrl).HasMaxLength(500).IsUnicode(false);
        e.Property(x => x.QrCode).HasMaxLength(1000).IsUnicode(false);
        e.Property(x => x.CreatedAt).HasDefaultValueSql("SYSUTCDATETIME()");

        // Mỗi orderCode của payOS ứng với đúng một giao dịch.
        e.HasIndex(x => x.ProviderOrderCode).IsUnique().HasFilter("[ProviderOrderCode] IS NOT NULL");

        e.HasOne(x => x.Order)
         .WithMany(o => o.Payments)
         .HasForeignKey(x => x.OrderId)
         .OnDelete(DeleteBehavior.Cascade);

        e.HasIndex(x => x.OrderId);
        e.HasIndex(x => x.TransactionRef).IsUnique().HasFilter("[TransactionRef] IS NOT NULL");
    }
}
