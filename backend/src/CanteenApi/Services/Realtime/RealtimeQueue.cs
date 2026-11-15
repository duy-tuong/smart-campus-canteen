using System.Threading.Channels;

namespace CanteenApi.Services.Realtime;

public enum RealtimeJobKind
{
    /// <summary>Ghi đè orders/{id} trên Firebase bằng trạng thái mới nhất trong SQL Server.</summary>
    Order,

    /// <summary>Ghi notifications/{uid}/{id}.</summary>
    Notification,

    /// <summary>Đánh dấu đã đọc toàn bộ notifications/{uid}.</summary>
    NotificationsReadAll,
}

/// <summary>Một việc đồng bộ. Không mang dữ liệu: khi xử lý luôn đọc trạng thái MỚI NHẤT từ SQL Server.</summary>
public sealed record RealtimeJob(RealtimeJobKind Kind, string Key, int Attempt = 0);

/// <summary>
/// Nơi nghiệp vụ báo "dữ liệu này vừa đổi, hãy đồng bộ lên Firebase".
/// Không chặn request: API trả kết quả ngay, việc ghi Firebase chạy nền và tự thử lại khi lỗi.
/// </summary>
public interface IRealtimePublisher
{
    void PublishOrder(string orderId);
    void PublishNotification(long notificationId);
    void PublishNotificationsRead(string userId);
}

/// <summary>Hàng đợi trong bộ nhớ (Channel) giữa nghiệp vụ và <see cref="RealtimeSyncWorker"/>.</summary>
public sealed class RealtimeQueue : IRealtimePublisher
{
    private readonly Channel<RealtimeJob> _channel = Channel.CreateUnbounded<RealtimeJob>(
        new UnboundedChannelOptions { SingleReader = true });

    public ChannelReader<RealtimeJob> Reader => _channel.Reader;

    public void Enqueue(RealtimeJob job) => _channel.Writer.TryWrite(job);

    public void PublishOrder(string orderId) => Enqueue(new RealtimeJob(RealtimeJobKind.Order, orderId));

    public void PublishNotification(long notificationId) =>
        Enqueue(new RealtimeJob(RealtimeJobKind.Notification, notificationId.ToString()));

    public void PublishNotificationsRead(string userId) =>
        Enqueue(new RealtimeJob(RealtimeJobKind.NotificationsReadAll, userId));
}
