using CanteenApi.Common;
using CanteenApi.Data;
using CanteenApi.Models;
using CanteenApi.Services.Notifications;
using CanteenApi.Services.Payments;
using CanteenApi.Services.Realtime;
using Microsoft.EntityFrameworkCore;

namespace CanteenApi.Services.Ordering;

/// <summary>
/// Vòng đời đơn hàng: chuyển trạng thái (staff) và hủy đơn (sinh viên / staff / hệ thống).
/// Mỗi thay đổi: ghi OrderStatusHistory + thông báo cho sinh viên trong CÙNG một lần lưu,
/// rồi (sau commit) đưa đơn vào hàng đợi đồng bộ realtime lên Firebase.
///
///   Received ──► Cooking ──► Ready ──► Completed
///      │            │
///      └────────────┴──► Cancelled   (sinh viên chỉ hủy khi Received; staff hủy khi Received/Cooking)
/// </summary>
public sealed class OrderLifecycleService(
    CanteenDbContext db,
    VoucherService vouchers,
    NotificationService notifications,
    IRealtimePublisher realtime,
    IPaymentGateway gateway,
    TimeProvider clock,
    ILogger<OrderLifecycleService> logger)
{
    /// <summary>Bảng chuyển trạng thái hợp lệ (hủy đơn đi qua <see cref="CancelByRequestAsync"/>).</summary>
    public static IReadOnlyList<OrderStatus> NextStatuses(OrderStatus status) => status switch
    {
        OrderStatus.Received => [OrderStatus.Cooking],
        OrderStatus.Cooking => [OrderStatus.Ready],
        OrderStatus.Ready => [OrderStatus.Completed],
        _ => [],
    };

    // ============================ Chuyển trạng thái (staff) ============================

    /// <summary>
    /// Staff chuyển trạng thái đơn theo bảng cố định.
    ///  - Đơn chuyển khoản phải thanh toán xong mới được nấu (PAYMENT_REQUIRED).
    ///  - Ready: cập nhật giờ xong thực tế.
    ///  - Completed + tiền mặt: ghi nhận đã thu tiền tại quầy.
    /// Hai staff bấm cùng lúc → RowVersion bảo đảm chỉ một người thành công (người sau nhận 409).
    /// </summary>
    public async Task ChangeStatusAsync(string orderId, OrderStatus to, string? note, string actorUid, CancellationToken ct)
    {
        var order = await LoadForUpdateAsync(orderId, ct) ?? throw new NotFoundException("Không tìm thấy đơn hàng.");

        if (to == OrderStatus.Cancelled)
            throw new BusinessRuleException(ErrorCodes.InvalidStatusTransition,
                "Để hủy đơn, hãy dùng chức năng Hủy đơn (POST /api/orders/{id}/cancel) và nhập lý do.");

        var allowed = NextStatuses(order.Status);
        if (!allowed.Contains(to))
            throw new BusinessRuleException(ErrorCodes.InvalidStatusTransition,
                    allowed.Count == 0
                        ? $"Đơn đang ở trạng thái {StatusText(order.Status)}, không thể chuyển tiếp."
                        : $"Không thể chuyển từ {StatusText(order.Status)} sang {StatusText(to)}.")
                .With("allowedStatuses", allowed);

        if (order.PaymentMethod == PaymentMethod.BankTransfer && order.PaymentStatus != PaymentStatus.Paid)
            throw new BusinessRuleException(ErrorCodes.PaymentRequired,
                "Đơn chuyển khoản chưa được thanh toán — chưa thể chế biến.");

        var now = clock.GetUtcNow().UtcDateTime;
        var from = order.Status;
        order.Status = to;

        if (to == OrderStatus.Ready) order.EstimatedReadyAt = now;

        if (to == OrderStatus.Completed && order.PaymentMethod == PaymentMethod.Cash && order.PaymentStatus == PaymentStatus.Pending)
        {
            // Tiền mặt: thu tiền khi giao món.
            var payment = order.Payments.Single(p => p.Status == PaymentStatus.Pending);
            payment.Status = PaymentStatus.Paid;
            payment.PaidAt = now;
            payment.TransactionRef = $"CASH-{order.PickupDate:yyMMdd}-{order.PickupCode}";
            order.PaymentStatus = PaymentStatus.Paid;
            order.PaidAt = now;
        }

        order.StatusHistory.Add(new OrderStatusHistory
        {
            FromStatus = from, ToStatus = to, ChangedByUserId = actorUid,
            Note = string.IsNullOrWhiteSpace(note) ? null : note.Trim(), ChangedAt = now,
        });

        var notification = notifications.ForOrder(order, to switch
        {
            OrderStatus.Cooking => OrderEvent.Cooking,
            OrderStatus.Ready => OrderEvent.Ready,
            _ => OrderEvent.Completed,
        });

        await db.SaveChangesAsync(ct);
        logger.LogInformation("Order {OrderId} #{Code}: {From} → {To} by {Actor}", order.Id, order.PickupCode, from, to, actorUid);

        realtime.PublishOrder(order.Id);
        realtime.PublishNotification(notification.Id);
    }

    // ============================ Hủy đơn ============================

    /// <summary>
    /// Hủy đơn theo yêu cầu: sinh viên hủy đơn của mình khi còn "Đã nhận"; staff/admin hủy khi "Đã nhận"/"Đang nấu".
    /// Đơn của người khác → 404 (không lộ đơn có tồn tại).
    /// </summary>
    public async Task CancelByRequestAsync(string orderId, string actorUid, bool isStaff, string reason, CancellationToken ct)
    {
        var order = await LoadForUpdateAsync(orderId, ct);
        if (order is null || (!isStaff && order.UserId != actorUid))
            throw new NotFoundException("Không tìm thấy đơn hàng.");

        if (!OrderService.CanCancel(order.Status, isStaff, order.UserId == actorUid))
            throw new BusinessRuleException(ErrorCodes.OrderNotCancellable, order.Status switch
            {
                OrderStatus.Cancelled => "Đơn đã được hủy trước đó.",
                OrderStatus.Completed => "Đơn đã hoàn thành, không thể hủy.",
                OrderStatus.Ready => "Món đã chuẩn bị xong, không thể hủy. Vui lòng liên hệ quầy.",
                _ => "Căn-tin đang chế biến món, bạn không thể tự hủy. Vui lòng liên hệ quầy.",
            });

        await CancelAsync(order, reason.Trim(), actorUid, ct);
    }

    /// <summary>
    /// Hủy đơn (đơn phải đang được theo dõi bởi DbContext, kèm Payments):
    ///  - Status = Cancelled, lưu lý do, ghi lịch sử (actorUid null = hệ thống)
    ///  - trả lại lượt voucher; số suất tự được hoàn vì đơn hủy không được đếm
    ///  - thanh toán đang chờ → Failed và hủy link payOS (lỗi chỉ ghi log)
    ///  - đã thanh toán → Refunded + bản ghi hoàn tiền để staff hoàn tiền thủ công
    ///  - báo cho sinh viên (trừ khi chính sinh viên tự hủy)
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

        var notification = actorUid == order.UserId ? null : notifications.ForOrder(order, OrderEvent.Cancelled);

        await db.SaveChangesAsync(ct);
        if (order.VoucherId is { } voucherId) await vouchers.ReleaseAsync(voucherId, ct);
        await tx.CommitAsync(ct);

        logger.LogInformation("Order {OrderId} cancelled by {Actor}: {Reason}", order.Id, actorUid ?? "system", reason);
        realtime.PublishOrder(order.Id);
        if (notification is not null) realtime.PublishNotification(notification.Id);

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
    }

    /// <summary>Tải đơn kèm Payments để cập nhật (RowVersion phát hiện thay đổi đồng thời).</summary>
    public Task<Order?> LoadForUpdateAsync(string orderId, CancellationToken ct) =>
        db.Orders.Include(o => o.Payments).FirstOrDefaultAsync(o => o.Id == orderId, ct);

    private static string StatusText(OrderStatus s) => s switch
    {
        OrderStatus.Received => "\"Đã nhận\"",
        OrderStatus.Cooking => "\"Đang nấu\"",
        OrderStatus.Ready => "\"Mời nhận món\"",
        OrderStatus.Completed => "\"Hoàn thành\"",
        _ => "\"Đã hủy\"",
    };
}
