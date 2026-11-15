using System.Collections.Concurrent;
using CanteenApi.Services.Realtime;

namespace CanteenApi.Tests.Infrastructure;

/// <summary>Ghi lại các việc đồng bộ realtime được yêu cầu (test không ghi lên Firebase thật).</summary>
public sealed class FakeRealtimePublisher : IRealtimePublisher
{
    public ConcurrentQueue<string> Orders { get; } = new();
    public ConcurrentQueue<long> Notifications { get; } = new();
    public ConcurrentQueue<string> ReadAll { get; } = new();

    public void Reset()
    {
        Orders.Clear();
        Notifications.Clear();
        ReadAll.Clear();
    }

    public void PublishOrder(string orderId) => Orders.Enqueue(orderId);
    public void PublishNotification(long notificationId) => Notifications.Enqueue(notificationId);
    public void PublishNotificationsRead(string userId) => ReadAll.Enqueue(userId);
}
