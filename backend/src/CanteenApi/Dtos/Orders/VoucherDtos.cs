using System.ComponentModel.DataAnnotations;
using CanteenApi.Common;
using CanteenApi.Models;

namespace CanteenApi.Dtos.Orders;

/// <summary>Voucher hiển thị cho sinh viên.</summary>
public sealed record AvailableVoucherDto(
    string Code,
    string Description,
    DiscountType DiscountType,
    int DiscountValue,
    int? MaxDiscount,
    int MinOrderAmount,
    DateTime EndAt,
    /// <summary>Số lần tôi còn dùng được; null = không giới hạn.</summary>
    int? RemainingForMe);

/// <summary>Voucher trong màn quản lý (staff/admin).</summary>
public sealed record VoucherDto(
    int Id,
    string Code,
    string Description,
    DiscountType DiscountType,
    int DiscountValue,
    int? MaxDiscount,
    int MinOrderAmount,
    DateTime StartAt,
    DateTime EndAt,
    int? UsageLimit,
    int UsedCount,
    int? PerUserLimit,
    bool IsActive,
    /// <summary>Số đơn (kể cả đã hủy) từng dùng mã này — &gt; 0 thì không được xóa/đổi mã.</summary>
    int OrderCount,
    string RowVersion,
    DateTime CreatedAt,
    DateTime UpdatedAt);

public sealed class VoucherQuery : PageQuery
{
    [StringLength(30)]
    public string? Q { get; set; }

    public bool? IsActive { get; set; }
}

/// <summary>Tạo / sửa voucher.</summary>
public sealed record SaveVoucherRequest(
    [Required(ErrorMessage = "Vui lòng nhập mã.")]
    [RegularExpression("^[A-Za-z0-9]{3,30}$", ErrorMessage = "Mã gồm 3–30 chữ cái hoặc số, không dấu, không khoảng trắng.")]
    string Code,

    [Required(ErrorMessage = "Vui lòng nhập mô tả.")]
    [StringLength(300, MinimumLength = 5, ErrorMessage = "Mô tả dài từ 5 đến 300 ký tự.")]
    string Description,

    [Required(ErrorMessage = "Vui lòng chọn kiểu giảm (percent | fixed).")]
    DiscountType? DiscountType,

    [Range(1, 1_000_000, ErrorMessage = "Giá trị giảm không hợp lệ.")]
    int DiscountValue,

    [Range(1_000, 1_000_000, ErrorMessage = "Mức giảm tối đa từ 1.000đ đến 1.000.000đ.")]
    int? MaxDiscount,

    [Range(0, 10_000_000, ErrorMessage = "Giá trị đơn tối thiểu không hợp lệ.")]
    int MinOrderAmount,

    [Required(ErrorMessage = "Vui lòng nhập thời gian bắt đầu.")]
    DateTimeOffset? StartAt,

    [Required(ErrorMessage = "Vui lòng nhập thời gian kết thúc.")]
    DateTimeOffset? EndAt,

    [Range(1, 1_000_000, ErrorMessage = "Tổng lượt dùng phải ≥ 1 (để trống nếu không giới hạn).")]
    int? UsageLimit,

    [Range(1, 1000, ErrorMessage = "Lượt dùng mỗi người phải ≥ 1 (để trống nếu không giới hạn).")]
    int? PerUserLimit,

    bool? IsActive,

    /// <summary>Bắt buộc khi sửa (PUT); bỏ qua khi tạo.</summary>
    string? RowVersion) : IValidatableObject
{
    public IEnumerable<ValidationResult> Validate(ValidationContext context)
    {
        if (DiscountType == Models.DiscountType.Percent && DiscountValue > 100)
            yield return new ValidationResult("Giảm theo phần trăm tối đa 100%.", [nameof(DiscountValue)]);

        if (DiscountType == Models.DiscountType.Fixed && MaxDiscount is not null)
            yield return new ValidationResult("Mức giảm tối đa chỉ dùng cho giảm theo phần trăm.", [nameof(MaxDiscount)]);

        if (StartAt is { } start && EndAt is { } end && end <= start)
            yield return new ValidationResult("Thời gian kết thúc phải sau thời gian bắt đầu.", [nameof(EndAt)]);
    }
}

public sealed record UpdateVoucherStatusRequest(
    [Required(ErrorMessage = "Vui lòng cho biết trạng thái isActive.")]
    bool? IsActive);
