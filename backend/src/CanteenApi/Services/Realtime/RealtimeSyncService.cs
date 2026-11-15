using System.Text.Json;
using CanteenApi.Data;
using CanteenApi.Models;
using Microsoft.EntityFrameworkCore;

namespace CanteenApi.Services.Realtime;

/// <summary>
/// Ghi bản sao realtime lên Firebase Realtime Database. SQL Server là nguồn dữ liệu chính;
/// mỗi lần đồng bộ đọc trạng thái MỚI NHẤT rồi GHI ĐÈ node → chạy lại bao nhiêu lần cũng không sai.
///
/// Cấu trúc trên Firebase (app chỉ được ĐỌC, theo Security Rules):
///   orders/{orderId}             — sinh viên nghe đơn của mình, staff nghe theo status
///   notifications/{uid}/n{id}    — thông báo của từng người
/// </summary>
public sealed class RealtimeSyncService(CanteenDbContext db, FirebaseDbService rtdb, TimeProvider clock)
{
    private static readonly OrderStatus[] ActiveStatuses = [OrderStatus.Received, OrderStatus.Cooking, OrderStatus.Ready];

    public Task ProcessAsync(RealtimeJob job, CancellationToken ct) => job.Kind switch
    {
        RealtimeJobKind.Order => SyncOrderAsync(job.Key, ct),
        RealtimeJobKind.Notification => SyncNotificationAsync(long.Parse(job.Key), ct),
        RealtimeJobKind.NotificationsReadAll => SyncReadAllAsync(job.Key, ct),
        _ => Task.CompletedTask,
    };

    public async Task SyncOrderAsync(string orderId, CancellationToken ct)
    {
        var order = await db.Orders.AsNoTracking().AsSplitQuery()
            .Include(o => o.User)
            .Include(o => o.Items).ThenInclude(i => i.Options)
            .FirstOrDefaultAsync(o => o.Id == orderId, ct);

        if (order is null)
            await rtdb.DeleteAsync($"orders/{orderId}", ct);
        else
            await rtdb.SetAsync($"orders/{orderId}", OrderPayload(order), ct);
    }

    public async Task SyncNotificationAsync(long id, CancellationToken ct)
    {
        var n = await db.Notifications.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        if (n is not null) await rtdb.SetAsync($"notifications/{n.UserId}/{NotificationKey(n.Id)}", NotificationPayload(n), ct);
    }

    /// <summary>
    /// Khóa thông báo trên Firebase có tiền tố "n" ("n12" thay vì "12"): khóa toàn số liên tiếp bị
    /// Realtime Database tự chuyển thành MẢNG, khiến app lúc nhận Map lúc nhận List.
    /// </summary>
    public static string NotificationKey(long id) => $"n{id}";

    /// <summary>Đánh dấu đã đọc trên Firebase bằng MỘT lệnh cập nhật nhiều đường dẫn ("123/isRead": true...).</summary>
    public async Task SyncReadAllAsync(string userId, CancellationToken ct)
    {
        var ids = await db.Notifications.AsNoTracking()
            .Where(n => n.UserId == userId && n.IsRead)
            .OrderByDescending(n => n.Id).Take(200)
            .Select(n => n.Id).ToListAsync(ct);
        if (ids.Count == 0) return;

        await rtdb.UpdateAsync($"notifications/{userId}",
            ids.ToDictionary(id => $"{NotificationKey(id)}/isRead", _ => (object)true), ct);
    }

    /// <summary>Đồng bộ lại mọi đơn đang xử lý (khi server khởi động — phòng việc bị mất khi tắt máy giữa chừng).</summary>
    public async Task<int> ResyncActiveOrdersAsync(CancellationToken ct)
    {
        var ids = await db.Orders.AsNoTracking().Where(o => ActiveStatuses.Contains(o.Status)).Select(o => o.Id).ToListAsync(ct);
        foreach (var id in ids) await SyncOrderAsync(id, ct);
        return ids.Count;
    }

    /// <summary>Xóa khỏi Firebase các đơn đã xong/đã hủy hơn 24 giờ (giữ Firebase gọn, trong hạn mức miễn phí).</summary>
    public async Task<int> CleanupFinishedOrdersAsync(CancellationToken ct)
    {
        var now = clock.GetUtcNow().UtcDateTime;
        var ids = await db.Orders.AsNoTracking()
            .Where(o => (o.Status == OrderStatus.Completed || o.Status == OrderStatus.Cancelled) &&
                        o.UpdatedAt < now.AddHours(-24) && o.UpdatedAt >= now.AddHours(-72))
            .Select(o => o.Id).ToListAsync(ct);
        foreach (var id in ids) await rtdb.DeleteAsync($"orders/{id}", ct);
        return ids.Count;
    }

    /// <summary>Dữ liệu một đơn trên Firebase (enum ghi dạng chuỗi camelCase, thời gian dạng epoch mili-giây).</summary>
    public static Dictionary<string, object?> OrderPayload(Order o) => new()
    {
        ["userId"] = o.UserId,
        ["customerName"] = o.User?.FullName,
        ["pickupCode"] = o.PickupCode,
        ["status"] = Camel(o.Status),
        ["paymentMethod"] = Camel(o.PaymentMethod),
        ["paymentStatus"] = Camel(o.PaymentStatus),
        ["totalAmount"] = o.TotalAmount,
        ["totalItems"] = o.Items.Sum(i => i.Quantity),
        ["items"] = o.Items.OrderBy(i => i.Id).Select(i => new Dictionary<string, object?>
        {
            ["name"] = i.FoodName,
            ["quantity"] = i.Quantity,
            ["options"] = string.Join(", ", i.Options.OrderBy(x => x.Id).Select(x => x.OptionName)),
            ["note"] = i.Note,
        }).ToList(),
        ["note"] = o.Note,
        ["cancelReason"] = o.CancelReason,
        ["pickupTime"] = Epoch(o.PickupTime),
        ["estimatedReadyAt"] = Epoch(o.EstimatedReadyAt),
        ["createdAt"] = Epoch(o.CreatedAt),
        ["updatedAt"] = Epoch(o.UpdatedAt),
    };

    public static Dictionary<string, object?> NotificationPayload(Notification n) => new()
    {
        ["title"] = n.Title,
        ["body"] = n.Body,
        ["type"] = Camel(n.Type),
        ["refId"] = n.RefId,
        ["isRead"] = n.IsRead,
        ["createdAt"] = Epoch(n.CreatedAt),
    };

    private static string Camel<T>(T value) where T : struct, Enum => JsonNamingPolicy.CamelCase.ConvertName(value.ToString());

    private static long? Epoch(DateTime? utc) =>
        utc is { } v ? new DateTimeOffset(DateTime.SpecifyKind(v, DateTimeKind.Utc)).ToUnixTimeMilliseconds() : null;
}
