using CanteenApi.Common;
using CanteenApi.Data;
using CanteenApi.Models;
using CanteenApi.Services.Realtime;
using Microsoft.EntityFrameworkCore;

namespace CanteenApi.Services.Notifications;

public sealed record NotificationDto(
    long Id, string Title, string Body, NotificationType Type, string? RefId, bool IsRead, DateTime CreatedAt);

/// <summary>Trang thông báo kèm số chưa đọc (để app hiện badge).</summary>
public sealed record NotificationListDto(
    IReadOnlyList<NotificationDto> Items, int Page, int PageSize, int TotalCount, int UnreadCount);

/// <summary>
/// Thông báo trong app. Bản ghi lâu dài ở SQL Server (bảng Notifications);
/// bản sao realtime ở Firebase notifications/{uid}/{id} để app nhận ngay.
/// </summary>
public sealed class NotificationService(CanteenDbContext db, IRealtimePublisher realtime, TimeProvider clock)
{
    // ============================ Nội dung theo sự kiện đơn hàng ============================

    /// <summary>Tạo (chưa lưu) thông báo cho chủ đơn — gọi trước SaveChanges để ghi cùng transaction với thay đổi đơn.</summary>
    public Notification ForOrder(Order order, OrderEvent kind)
    {
        var code = $"#{order.PickupCode}";
        var (title, body) = kind switch
        {
            OrderEvent.Placed when order.PaymentMethod == PaymentMethod.BankTransfer =>
                ($"Đặt món thành công {code}", $"Vui lòng chuyển khoản {Money.Format(order.TotalAmount)} để căn-tin bắt đầu chế biến."),
            OrderEvent.Placed => ($"Đặt món thành công {code}", $"Thanh toán {Money.Format(order.TotalAmount)} tại quầy khi nhận món."),
            OrderEvent.Paid => ($"Đã nhận thanh toán {code}", $"Căn-tin đã nhận {Money.Format(order.TotalAmount)}. Món của bạn sẽ sớm được chế biến."),
            OrderEvent.Cooking => ($"Đơn {code} đang được chế biến", "Căn-tin đang chuẩn bị món của bạn."),
            OrderEvent.Ready => ("Mời bạn nhận món", $"Đơn {code} đã xong. Mời bạn đến quầy nhận món!"),
            OrderEvent.Completed => ($"Đơn {code} đã hoàn thành",
                "Cảm ơn bạn! Chúc bạn ngon miệng. Hãy đánh giá món để giúp căn-tin phục vụ tốt hơn."),
            OrderEvent.Cancelled when order.PaymentStatus == PaymentStatus.Refunded =>
                ($"Đơn {code} đã bị hủy", $"Lý do: {order.CancelReason}. Căn-tin sẽ hoàn lại {Money.Format(order.TotalAmount)} cho bạn."),
            OrderEvent.Cancelled => ($"Đơn {code} đã bị hủy", $"Lý do: {order.CancelReason}."),
            _ => throw new ArgumentOutOfRangeException(nameof(kind)),
        };

        var notification = new Notification
        {
            UserId = order.UserId,
            Title = Truncate(title, 150),
            Body = Truncate(body, 500),
            Type = NotificationType.OrderStatus,
            RefId = order.Id,
            CreatedAt = clock.GetUtcNow().UtcDateTime,
        };
        db.Notifications.Add(notification);
        return notification;
    }

    /// <summary>Tạo (chưa lưu) thông báo "căn-tin đã trả lời đánh giá" cho tác giả.</summary>
    public Notification ForReviewReply(Review review, string foodName)
    {
        var notification = new Notification
        {
            UserId = review.UserId,
            Title = "Căn-tin đã trả lời đánh giá của bạn",
            Body = Truncate($"Về món {foodName}: \"{review.StaffReply}\"", 500),
            Type = NotificationType.Review,
            RefId = review.FoodId.ToString(),
            CreatedAt = clock.GetUtcNow().UtcDateTime,
        };
        db.Notifications.Add(notification);
        return notification;
    }

    // ============================ API của người dùng ============================

    public async Task<NotificationListDto> ListAsync(string uid, PageQuery query, CancellationToken ct)
    {
        var mine = db.Notifications.AsNoTracking().Where(n => n.UserId == uid);
        var page = await mine
            .OrderByDescending(n => n.CreatedAt).ThenByDescending(n => n.Id)
            .Select(n => new NotificationDto(n.Id, n.Title, n.Body, n.Type, n.RefId, n.IsRead, n.CreatedAt))
            .ToPagedResultAsync(query, ct);
        var unread = await mine.CountAsync(n => !n.IsRead, ct);

        return new NotificationListDto(page.Items, page.Page, page.PageSize, page.TotalCount, unread);
    }

    /// <summary>Đánh dấu đã đọc. Thông báo của người khác → 404.</summary>
    public async Task MarkReadAsync(string uid, long id, CancellationToken ct)
    {
        var updated = await db.Notifications.Where(n => n.Id == id && n.UserId == uid)
            .ExecuteUpdateAsync(s => s.SetProperty(n => n.IsRead, true), ct);
        if (updated == 0) throw new NotFoundException("Không tìm thấy thông báo.");
        realtime.PublishNotification(id);
    }

    public async Task<int> MarkAllReadAsync(string uid, CancellationToken ct)
    {
        var updated = await db.Notifications.Where(n => n.UserId == uid && !n.IsRead)
            .ExecuteUpdateAsync(s => s.SetProperty(n => n.IsRead, true), ct);
        if (updated > 0) realtime.PublishNotificationsRead(uid);
        return updated;
    }

    private static string Truncate(string value, int max) => value.Length <= max ? value : value[..(max - 1)] + "…";
}

/// <summary>Sự kiện của đơn hàng cần báo cho sinh viên.</summary>
public enum OrderEvent
{
    Placed,
    Paid,
    Cooking,
    Ready,
    Completed,
    Cancelled,
}
