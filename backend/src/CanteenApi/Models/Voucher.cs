namespace CanteenApi.Models;

/// <summary>Mã giảm giá. Bảng: Vouchers.</summary>
public class Voucher : IAuditable
{
    public int Id { get; set; }

    /// <summary>Mã nhập khi thanh toán, viết hoa, duy nhất (ví dụ "TANSV10").</summary>
    public string Code { get; set; } = string.Empty;

    public string Description { get; set; } = string.Empty;

    public DiscountType DiscountType { get; set; }

    /// <summary>Percent: 1–100 (%). Fixed: số tiền VNĐ.</summary>
    public int DiscountValue { get; set; }

    /// <summary>Mức giảm tối đa (VNĐ) khi giảm theo %; null = không giới hạn.</summary>
    public int? MaxDiscount { get; set; }

    /// <summary>Giá trị đơn tối thiểu (tạm tính) để áp dụng.</summary>
    public int MinOrderAmount { get; set; }

    public DateTime StartAt { get; set; }
    public DateTime EndAt { get; set; }

    /// <summary>Tổng số lượt dùng tối đa; null = không giới hạn.</summary>
    public int? UsageLimit { get; set; }

    /// <summary>Số lượt đã dùng (tăng khi đặt đơn, giảm khi đơn bị hủy).</summary>
    public int UsedCount { get; set; }

    /// <summary>Số lượt tối đa mỗi người; null = không giới hạn.</summary>
    public int? PerUserLimit { get; set; }

    public bool IsActive { get; set; } = true;

    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    /// <summary>Khóa lạc quan: tránh vượt UsageLimit khi nhiều người dùng mã cùng lúc.</summary>
    public byte[] RowVersion { get; set; } = [];

    public ICollection<Order> Orders { get; set; } = new List<Order>();
}
