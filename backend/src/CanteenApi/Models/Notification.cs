namespace CanteenApi.Models;

/// <summary>
/// Thông báo trong app. Bảng: Notifications (lưu lâu dài).
/// Khi tạo, backend đồng thời đẩy lên Firebase RTDB notifications/{uid}/{id} để app nhận realtime.
/// </summary>
public class Notification
{
    public long Id { get; set; }

    public string UserId { get; set; } = string.Empty;
    public AppUser? User { get; set; }

    public string Title { get; set; } = string.Empty;
    public string Body { get; set; } = string.Empty;
    public NotificationType Type { get; set; }

    /// <summary>Id đối tượng liên quan (ví dụ OrderId) để mở đúng màn hình khi bấm.</summary>
    public string? RefId { get; set; }

    public bool IsRead { get; set; }
    public DateTime CreatedAt { get; set; }
}
