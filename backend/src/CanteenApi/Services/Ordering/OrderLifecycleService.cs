using CanteenApi.Data;
using CanteenApi.Models;
using CanteenApi.Services.Payments;
using Microsoft.EntityFrameworkCore;

namespace CanteenApi.Services.Ordering;

/// <summary>
/// Vòng đời đơn hàng: hủy đơn (dùng chung cho sinh viên/staff hủy, hệ thống tự hủy khi lỗi thanh toán
/// hoặc quá hạn). Mọi thay đổi trạng thái đều ghi OrderStatusHistory.
/// </summary>
public sealed class OrderLifecycleService(
    CanteenDbContext db,
    VoucherService vouchers,
    IPaymentGateway gateway,
    TimeProvider clock,
    ILogger<OrderLifecycleService> logger)
{
    /// <summary>
    /// Hủy đơn (đơn phải đang được theo dõi bởi DbContext, kèm Payments):
    ///  - Status = Cancelled, lưu lý do, ghi lịch sử (actorUid null = hệ thống)
    ///  - trả lại lượt voucher; số suất tự được hoàn vì đơn hủy không được đếm
    ///  - thanh toán đang chờ → Failed và hủy link payOS (lỗi chỉ ghi log)
    ///  - đã thanh toán → Refunded + bản ghi hoàn tiền để staff hoàn tiền thủ công
    /// </summary>
    public async Task CancelAsync(Order order, string reason, string? actorUid, CancellationToken ct)
    {
        if (order.Status == OrderStatus.Cancelled) return;

        var now = clock.GetUtcNow().UtcDateTime;
        var from = order.Status;

        await using var tx = await db.Database.BeginTransactionAsync(ct);

        order.Status = OrderStatus.Cancelled;
        order.CancelReason = reason;
        order.StatusHistory.Add(new OrderStatusHistory
        {
            FromStatus = from, ToStatus = OrderStatus.Cancelled, ChangedByUserId = actorUid, Note = reason, ChangedAt = now,
        });

        long? linkToCancel = null;
        if (order.PaymentStatus == PaymentStatus.Paid)
        {
            // Tiền đã về: ghi nhận khoản phải hoàn (payOS không có API hoàn tiền chuyển khoản → staff hoàn thủ công).
            order.PaymentStatus = PaymentStatus.Refunded;
            order.Payments.Add(new Payment
            {
                Method = order.PaymentMethod, Amount = order.TotalAmount, Status = PaymentStatus.Refunded,
                PaidAt = order.PaidAt, CreatedAt = now,
            });
        }
        else
        {
            order.PaymentStatus = PaymentStatus.Failed;
            foreach (var payment in order.Payments.Where(p => p.Status == PaymentStatus.Pending))
            {
                payment.Status = PaymentStatus.Failed;
                linkToCancel ??= payment.ProviderOrderCode;
            }
        }

        await db.SaveChangesAsync(ct);
        if (order.VoucherId is { } voucherId) await vouchers.ReleaseAsync(voucherId, ct);
        await tx.CommitAsync(ct);

        logger.LogInformation("Order {OrderId} cancelled by {Actor}: {Reason}", order.Id, actorUid ?? "system", reason);

        // Hủy link thanh toán SAU khi commit: tránh khách vẫn quét QR trả tiền cho đơn đã hủy.
        if (linkToCancel is { } code && gateway.IsEnabled)
        {
            try
            {
                await gateway.CancelLinkAsync(code, reason, CancellationToken.None);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Không hủy được link payOS {OrderCode} của đơn {OrderId}", code, order.Id);
            }
        }

        // E4: tạo thông báo + đưa đơn vào hàng đợi đồng bộ realtime.
    }

    /// <summary>Tải đơn kèm Payments để cập nhật (đơn có thể đã bị đổi bởi request khác → dùng RowVersion).</summary>
    public Task<Order?> LoadForUpdateAsync(string orderId, CancellationToken ct) =>
        db.Orders.Include(o => o.Payments).FirstOrDefaultAsync(o => o.Id == orderId, ct);
}
