using System.ComponentModel.DataAnnotations;

namespace CanteenApi.Options;

/// <summary>Quy tắc vận hành căn-tin (section "Canteen" trong appsettings).</summary>
public sealed class CanteenOptions
{
    public const string SectionName = "Canteen";

    /// <summary>Giờ mở nhận đơn (giờ Việt Nam).</summary>
    public TimeOnly OpenTime { get; set; } = new(6, 30);

    /// <summary>Giờ ngừng nhận đơn (giờ Việt Nam).</summary>
    public TimeOnly CloseTime { get; set; } = new(19, 0);

    /// <summary>Số đơn đang xử lý tối đa của một người (chống đặt ảo/spam).</summary>
    [Range(1, 20)]
    public int MaxActiveOrdersPerUser { get; set; } = 3;

    /// <summary>Số dòng món tối đa trong một đơn.</summary>
    [Range(1, 50)]
    public int MaxLinesPerOrder { get; set; } = 20;

    /// <summary>Đơn chuyển khoản chưa thanh toán quá số phút này sẽ tự hủy.</summary>
    [Range(1, 120)]
    public int UnpaidTransferTimeoutMinutes { get; set; } = 15;

    /// <summary>Giờ hẹn lấy món tối thiểu sau thời điểm đặt (phút).</summary>
    [Range(0, 120)]
    public int MinPickupLeadMinutes { get; set; } = 10;

    /// <summary>
    /// URL public của backend (ví dụ URL tunnel cloudflared/ngrok) dùng cho returnUrl/cancelUrl và webhook payOS.
    /// Bỏ trống: dùng host của request hiện tại.
    /// </summary>
    public string? PublicBaseUrl { get; set; }
}

/// <summary>Các tác vụ chạy nền (section "Workers"). Môi trường test tắt để tự gọi từng lượt.</summary>
public sealed class WorkerOptions
{
    public const string SectionName = "Workers";

    public bool Enabled { get; set; } = true;

    /// <summary>Chu kỳ hỏi payOS trạng thái các khoản chuyển khoản đang chờ (giây).</summary>
    [Range(3, 600)]
    public int PaymentPollSeconds { get; set; } = 10;
}

/// <summary>Cấu hình cổng thanh toán payOS (section "PayOS"). Các khóa đặt trong user-secrets.</summary>
public sealed class PayOsOptions
{
    public const string SectionName = "PayOS";

    /// <summary>false: chỉ nhận thanh toán tiền mặt (khi chưa có tài khoản payOS).</summary>
    public bool Enabled { get; set; }

    public string ClientId { get; set; } = string.Empty;
    public string ApiKey { get; set; } = string.Empty;
    public string ChecksumKey { get; set; } = string.Empty;

    public bool IsConfigured =>
        Enabled && !string.IsNullOrWhiteSpace(ClientId) && !string.IsNullOrWhiteSpace(ApiKey) &&
        !string.IsNullOrWhiteSpace(ChecksumKey);
}
