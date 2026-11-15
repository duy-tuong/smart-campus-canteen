using CanteenApi.Auth;
using CanteenApi.Common;
using CanteenApi.Dtos.Orders;
using CanteenApi.Services.Ordering;
using Microsoft.AspNetCore.Mvc;

namespace CanteenApi.Controllers;

/// <summary>Đặt món và đơn hàng.</summary>
[ApiController]
[Route("api/orders")]
[Tags("Đơn hàng")]
public class OrdersController(OrderPricingService pricing, IPublicUrlBuilder urls, ICurrentUser me) : ControllerBase
{
    /// <summary>
    /// Báo giá giỏ hàng cho màn Thanh toán (KHÔNG tạo đơn): giá lấy từ database, lỗi theo từng dòng,
    /// kết quả kiểm tra voucher. Voucher không hợp lệ không chặn đặt hàng — chỉ không được giảm.
    /// </summary>
    [HttpPost("quote")]
    public async Task<QuoteDto> Quote([FromBody] QuoteRequest request, CancellationToken ct)
    {
        var result = await pricing.PriceAsync(request.Items, request.VoucherCode, me.Uid, ct);
        return new QuoteDto(
            result.Lines.Select(l => new PricedLineDto(
                l.Index, l.FoodId, l.FoodName, urls.Build(l.ImagePath), l.UnitPrice, l.OptionsPrice,
                l.Quantity, l.LineTotal, l.Note, l.Options)).ToList(),
            result.Errors,
            result.TotalItems,
            result.Subtotal,
            result.Voucher?.Check,
            result.DiscountAmount,
            result.TotalAmount,
            result.CanOrder);
    }
}
