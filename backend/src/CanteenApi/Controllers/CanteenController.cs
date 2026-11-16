using CanteenApi.Common;
using CanteenApi.Options;
using CanteenApi.Services.Payments;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;

namespace CanteenApi.Controllers;

/// <summary>Thông tin vận hành căn-tin cho app: giờ mở cửa, quy tắc đặt món, phương thức thanh toán đang bật.</summary>
/// <param name="OpenTime">Giờ bắt đầu nhận đơn (giờ Việt Nam, "HH:mm").</param>
/// <param name="CloseTime">Giờ ngừng nhận đơn (giờ Việt Nam, "HH:mm").</param>
/// <param name="IsOpen">Lúc này căn-tin có đang nhận đơn không.</param>
/// <param name="ServerTime">Giờ máy chủ (UTC) — app dùng để tính khung giờ hẹn, không phụ thuộc đồng hồ điện thoại.</param>
/// <param name="MinPickupLeadMinutes">Giờ hẹn lấy món sớm nhất = bây giờ + max(số phút này, thời gian chế biến lâu nhất).</param>
/// <param name="UnpaidTransferTimeoutMinutes">Đơn chuyển khoản chưa trả sau số phút này sẽ tự hủy.</param>
/// <param name="MaxActiveOrdersPerUser">Số đơn đang xử lý tối đa của một người.</param>
/// <param name="MaxLinesPerOrder">Số dòng món tối đa trong một đơn.</param>
/// <param name="BankTransferEnabled">Có nhận chuyển khoản (payOS) không; false → chỉ tiền mặt.</param>
public sealed record CanteenInfoDto(
    string OpenTime,
    string CloseTime,
    bool IsOpen,
    DateTime ServerTime,
    int MinPickupLeadMinutes,
    int UnpaidTransferTimeoutMinutes,
    int MaxActiveOrdersPerUser,
    int MaxLinesPerOrder,
    bool BankTransferEnabled);

[ApiController]
[Route("api/canteen")]
[Tags("Căn-tin")]
[AllowAnonymous]
public class CanteenController(IOptions<CanteenOptions> options, TimeProvider clock, IPaymentGateway gateway) : ControllerBase
{
    /// <summary>Giờ mở cửa và quy tắc đặt món (không cần đăng nhập).</summary>
    [HttpGet("info")]
    [ProducesResponseType<CanteenInfoDto>(StatusCodes.Status200OK)]
    public CanteenInfoDto GetInfo()
    {
        var o = options.Value;
        var nowVn = TimeOnly.FromDateTime(VietnamTime.Now(clock));
        return new CanteenInfoDto(
            o.OpenTime.ToString("HH:mm"),
            o.CloseTime.ToString("HH:mm"),
            nowVn >= o.OpenTime && nowVn < o.CloseTime,
            clock.GetUtcNow().UtcDateTime,
            o.MinPickupLeadMinutes,
            o.UnpaidTransferTimeoutMinutes,
            o.MaxActiveOrdersPerUser,
            o.MaxLinesPerOrder,
            gateway.IsEnabled);
    }
}
