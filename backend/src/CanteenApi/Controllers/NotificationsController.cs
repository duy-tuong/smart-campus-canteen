using CanteenApi.Auth;
using CanteenApi.Common;
using CanteenApi.Services.Notifications;
using Microsoft.AspNetCore.Mvc;

namespace CanteenApi.Controllers;

/// <summary>Thông báo của tôi (bản lâu dài trong SQL Server; app nhận realtime qua Firebase notifications/{uid}).</summary>
[ApiController]
[Route("api/notifications")]
[Tags("Thông báo")]
public class NotificationsController(NotificationService notifications, ICurrentUser me) : ControllerBase
{
    /// <summary>Danh sách thông báo (mới nhất trước) kèm số chưa đọc.</summary>
    [HttpGet]
    public async Task<NotificationListDto> List([FromQuery] PageQuery query, CancellationToken ct) =>
        await notifications.ListAsync(me.Uid, query, ct);

    /// <summary>Đánh dấu một thông báo đã đọc.</summary>
    [HttpPatch("{id:long}/read")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> MarkRead(long id, CancellationToken ct)
    {
        await notifications.MarkReadAsync(me.Uid, id, ct);
        return NoContent();
    }

    /// <summary>Đánh dấu tất cả đã đọc. Trả về số thông báo vừa được đánh dấu.</summary>
    [HttpPost("read-all")]
    public async Task<IActionResult> MarkAllRead(CancellationToken ct) =>
        Ok(new { updated = await notifications.MarkAllReadAsync(me.Uid, ct) });
}
