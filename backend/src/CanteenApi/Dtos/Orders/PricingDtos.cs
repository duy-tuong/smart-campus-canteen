using System.ComponentModel.DataAnnotations;

namespace CanteenApi.Dtos.Orders;

// Quy ước: với record, attribute validate đặt trên THAM SỐ constructor.

/// <summary>Một dòng trong giỏ hàng. Client KHÔNG gửi giá — server tự tính từ database.</summary>
public sealed record CartLineRequest(
    [Range(1, int.MaxValue, ErrorMessage = "Món không hợp lệ.")]
    int FoodId,

    [Range(1, 50, ErrorMessage = "Số lượng mỗi món từ 1 đến 50.")]
    int Quantity,

    /// <summary>Id các tùy chọn đã chọn (size, topping...).</summary>
    [MaxLength(30, ErrorMessage = "Chọn quá nhiều tùy chọn.")]
    List<int>? OptionIds,

    [StringLength(200, ErrorMessage = "Ghi chú món tối đa 200 ký tự.")]
    string? Note);

/// <summary>Yêu cầu báo giá giỏ hàng (màn Thanh toán) — không tạo đơn.</summary>
public sealed record QuoteRequest(
    [Required(ErrorMessage = "Giỏ hàng trống.")]
    [MinLength(1, ErrorMessage = "Giỏ hàng trống.")]
    [MaxLength(50, ErrorMessage = "Giỏ hàng quá nhiều dòng.")]
    List<CartLineRequest> Items,

    [StringLength(30, ErrorMessage = "Mã giảm giá tối đa 30 ký tự.")]
    string? VoucherCode);

public sealed record PricedOptionDto(int OptionId, string GroupName, string OptionName, int ExtraPrice);

/// <summary>Một dòng đã được server tính giá.</summary>
public sealed record PricedLineDto(
    int Index,
    int FoodId,
    string FoodName,
    string? ImageUrl,
    int UnitPrice,
    int OptionsPrice,
    int Quantity,
    int LineTotal,
    string? Note,
    IReadOnlyList<PricedOptionDto> Options);

/// <summary>Lỗi của một dòng giỏ hàng (để app tô đỏ đúng món).</summary>
public sealed record LineErrorDto(
    int Index,
    int FoodId,
    string Code,
    string Message,
    /// <summary>Với ITEM_SOLD_OUT: số suất còn lại hôm nay.</summary>
    int? Remaining = null);

/// <summary>Kết quả kiểm tra voucher.</summary>
public sealed record VoucherCheckDto(
    string Code,
    bool IsValid,
    int Discount,
    string? ErrorCode,
    string Message);

/// <summary>Báo giá đầy đủ của giỏ hàng.</summary>
public sealed record QuoteDto(
    IReadOnlyList<PricedLineDto> Lines,
    IReadOnlyList<LineErrorDto> Errors,
    int TotalItems,
    int Subtotal,
    VoucherCheckDto? Voucher,
    int DiscountAmount,
    int TotalAmount,
    /// <summary>true khi mọi dòng hợp lệ (voucher không hợp lệ không chặn đặt hàng — chỉ không được giảm).</summary>
    bool CanOrder);
