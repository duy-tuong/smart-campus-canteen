using System.ComponentModel.DataAnnotations;
using CanteenApi.Common;
using CanteenApi.Models;

namespace CanteenApi.Dtos.Orders;

// Quy ước: với record, attribute validate đặt trên THAM SỐ constructor.

/// <summary>
/// Đặt món. Kèm header bắt buộc "Idempotency-Key" (GUID do app sinh cho mỗi lần bấm Đặt món):
/// gửi lại cùng key khi mạng chập chờn sẽ nhận lại đơn cũ thay vì tạo đơn trùng.
/// </summary>
public sealed record CreateOrderRequest(
    [Required(ErrorMessage = "Giỏ hàng trống.")]
    [MinLength(1, ErrorMessage = "Giỏ hàng trống.")]
    [MaxLength(50, ErrorMessage = "Giỏ hàng quá nhiều dòng.")]
    List<CartLineRequest> Items,

    [StringLength(30, ErrorMessage = "Mã giảm giá tối đa 30 ký tự.")]
    string? VoucherCode,

    [Required(ErrorMessage = "Vui lòng chọn phương thức thanh toán (cash | bankTransfer).")]
    PaymentMethod? PaymentMethod,

    /// <summary>Giờ hẹn lấy món (trong hôm nay, giờ mở cửa). Bỏ trống = lấy ngay khi xong.</summary>
    DateTimeOffset? PickupTime,

    [StringLength(300, ErrorMessage = "Ghi chú tối đa 300 ký tự.")]
    string? Note);

public sealed record OrderItemOptionDto(string GroupName, string OptionName, int ExtraPrice);

public sealed record OrderItemDto(
    int Id,
    /// <summary>null nếu món đã bị xóa khỏi thực đơn (hóa đơn vẫn giữ tên/giá).</summary>
    int? FoodId,
    string FoodName,
    string? ImageUrl,
    int UnitPrice,
    int OptionsPrice,
    int Quantity,
    int LineTotal,
    string? Note,
    IReadOnlyList<OrderItemOptionDto> Options);

/// <summary>Một mốc trên dòng thời gian trạng thái đơn.</summary>
public sealed record OrderStatusEventDto(
    OrderStatus? FromStatus,
    OrderStatus ToStatus,
    string ChangedByName,
    string? Note,
    DateTime ChangedAt);

/// <summary>
/// Thông tin thanh toán của đơn. Với chuyển khoản đang chờ trả: app vẽ mã QR từ <see cref="QrCode"/>
/// (chuỗi VietQR) hoặc mở <see cref="CheckoutUrl"/>; hiển thị số tài khoản + nội dung để chuyển tay.
/// </summary>
public sealed record PaymentInfoDto(
    PaymentMethod Method,
    PaymentStatus Status,
    int Amount,
    DateTime? PaidAt,
    string? CheckoutUrl,
    string? QrCode,
    DateTime? ExpiresAt,
    /// <summary>Nội dung chuyển khoản (bắt buộc ghi đúng để hệ thống tự nhận tiền).</summary>
    string? TransferContent,
    string? BankBin,
    string? BankAccountNumber,
    string? BankAccountName);

public sealed record OrderCustomerDto(string Id, string FullName, string? StudentCode, string? Phone);

public sealed record OrderDetailDto(
    string Id,
    string PickupCode,
    DateOnly PickupDate,
    OrderStatus Status,
    PaymentMethod PaymentMethod,
    PaymentStatus PaymentStatus,
    DateTime? PaidAt,
    int Subtotal,
    int DiscountAmount,
    int TotalAmount,
    int TotalItems,
    string? VoucherCode,
    string? Note,
    string? CancelReason,
    DateTime? PickupTime,
    DateTime? EstimatedReadyAt,
    DateTime CreatedAt,
    DateTime UpdatedAt,
    OrderCustomerDto Customer,
    IReadOnlyList<OrderItemDto> Items,
    IReadOnlyList<OrderStatusEventDto> History,
    PaymentInfoDto? Payment,
    /// <summary>Người đang xem có được hủy đơn này không (để app ẩn/hiện nút Hủy).</summary>
    bool CanCancel,
    /// <summary>Chỉ với staff/admin: trạng thái được chuyển tiếp (để app hiện đúng nút "Bắt đầu nấu", "Xong món"...).</summary>
    IReadOnlyList<OrderStatus> AllowedNextStatuses);

/// <summary>Staff chuyển trạng thái đơn.</summary>
public sealed record UpdateOrderStatusRequest(
    [Required(ErrorMessage = "Vui lòng chọn trạng thái mới (cooking | ready | completed).")]
    OrderStatus? Status,
    [StringLength(300, ErrorMessage = "Ghi chú tối đa 300 ký tự.")]
    string? Note);

/// <summary>Hủy đơn (bắt buộc nêu lý do — hiển thị cho khách và lưu vào lịch sử).</summary>
public sealed record CancelOrderRequest(
    [Required(ErrorMessage = "Vui lòng nhập lý do hủy.")]
    [StringLength(300, MinimumLength = 5, ErrorMessage = "Lý do hủy dài từ 5 đến 300 ký tự.")]
    string Reason);

public sealed record OrderSummaryDto(
    string Id,
    string PickupCode,
    OrderStatus Status,
    PaymentMethod PaymentMethod,
    PaymentStatus PaymentStatus,
    int TotalAmount,
    int TotalItems,
    /// <summary>Tóm tắt món, ví dụ "Cơm gà xối mỡ ×2, Trà sữa trân châu ×1".</summary>
    string ItemsPreview,
    string CustomerName,
    string? StudentCode,
    DateTime? PickupTime,
    DateTime? EstimatedReadyAt,
    DateTime CreatedAt);

/// <summary>Bộ lọc "Đơn của tôi".</summary>
public sealed class MyOrdersQuery : PageQuery
{
    /// <summary>active (đang xử lý) | completed | cancelled. Bỏ trống = tất cả.</summary>
    [RegularExpression("^(active|completed|cancelled)$", ErrorMessage = "status phải là: active, completed, cancelled.")]
    public string? Status { get; set; }
}

/// <summary>Bộ lọc bảng đơn của căn-tin (staff/admin).</summary>
public sealed class StaffOrdersQuery : PageQuery
{
    /// <summary>Lọc nhiều trạng thái: ?status=received&amp;status=cooking</summary>
    public List<OrderStatus>? Status { get; set; }

    /// <summary>Ngày (giờ Việt Nam), mặc định hôm nay.</summary>
    public DateOnly? Date { get; set; }

    /// <summary>Mã nhận món (có hoặc không có dấu #), họ tên (không dấu) hoặc MSSV.</summary>
    [StringLength(100)]
    public string? Q { get; set; }

    public PaymentStatus? PaymentStatus { get; set; }
}
