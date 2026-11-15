using CanteenApi.Auth;
using CanteenApi.Common;
using CanteenApi.Dtos.Orders;
using CanteenApi.Services.Ordering;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CanteenApi.Controllers;

/// <summary>Đặt món và đơn hàng.</summary>
[ApiController]
[Route("api/orders")]
[Tags("Đơn hàng")]
public class OrdersController(
    OrderPricingService pricing,
    OrderService orders,
    IPublicUrlBuilder urls,
    ICurrentUser me) : ControllerBase
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

    /// <summary>
    /// Đặt món. Bắt buộc header <c>Idempotency-Key</c> (GUID mới cho mỗi lần bấm "Đặt món"):
    /// gửi lại cùng key (mạng chập chờn) sẽ nhận lại đơn cũ với mã 200 thay vì tạo đơn trùng.
    /// </summary>
    /// <response code="201">Đã tạo đơn.</response>
    /// <response code="200">Idempotency-Key đã dùng — trả lại đơn đã tạo trước đó.</response>
    /// <response code="422">ORDER_ITEMS_INVALID (kèm items[]), CANTEEN_CLOSED, PICKUP_TIME_INVALID,
    /// TOO_MANY_ACTIVE_ORDERS, PAYMENT_METHOD_UNAVAILABLE, VOUCHER_*.</response>
    [HttpPost]
    [ProducesResponseType<OrderDetailDto>(StatusCodes.Status201Created)]
    [ProducesResponseType<OrderDetailDto>(StatusCodes.Status200OK)]
    public async Task<IActionResult> Create(
        [FromBody] CreateOrderRequest request,
        [FromHeader(Name = "Idempotency-Key")] string? idempotencyKey,
        CancellationToken ct)
    {
        var (order, created) = await orders.CreateAsync(me.Uid, idempotencyKey, request, ct);
        return created ? CreatedAtAction(nameof(Get), new { id = order.Id }, order) : Ok(order);
    }

    /// <summary>Đơn của tôi (lọc active | completed | cancelled), mới nhất trước.</summary>
    [HttpGet("me")]
    public async Task<PagedResult<OrderSummaryDto>> ListMine([FromQuery] MyOrdersQuery query, CancellationToken ct) =>
        await orders.ListMineAsync(me.Uid, query, ct);

    /// <summary>Chi tiết đơn (chủ đơn hoặc staff/admin): món, tùy chọn, dòng thời gian trạng thái, thanh toán.</summary>
    [HttpGet("{id}")]
    [ProducesResponseType<OrderDetailDto>(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<OrderDetailDto> Get(string id, CancellationToken ct) =>
        await orders.GetDetailAsync(id, me.Uid, me.IsStaffOrAdmin, ct);

    /// <summary>
    /// Kiểm tra ngay trạng thái thanh toán với payOS (app gọi khi người dùng bấm "Tôi đã chuyển khoản").
    /// Trả về chi tiết đơn sau khi đồng bộ.
    /// </summary>
    [HttpPost("{id}/payment/sync")]
    public async Task<OrderDetailDto> SyncPayment(string id, [FromServices] Services.Payments.PaymentService payments,
        CancellationToken ct)
    {
        await payments.SyncOrderAsync(id, me.Uid, me.IsStaffOrAdmin, ct);
        return await orders.GetDetailAsync(id, me.Uid, me.IsStaffOrAdmin, ct);
    }

    /// <summary>Staff xác nhận đã nhận tiền (khách đưa ảnh chụp chuyển khoản / trả tiền trước tại quầy).</summary>
    /// <response code="422">PAYMENT_NOT_PENDING — đơn đã thanh toán hoặc đã hủy.</response>
    [HttpPost("{id}/payment/confirm")]
    [Authorize(Policy = Policies.StaffOrAdmin)]
    public async Task<OrderDetailDto> ConfirmPayment(string id, [FromServices] Services.Payments.PaymentService payments,
        CancellationToken ct)
    {
        await payments.ConfirmManuallyAsync(id, me.Uid, ct);
        return await orders.GetDetailAsync(id, me.Uid, isStaff: true, ct);
    }

    /// <summary>
    /// Bảng đơn của căn-tin: theo ngày (mặc định hôm nay), lọc nhiều trạng thái
    /// (?status=received&amp;status=cooking), tìm theo mã nhận món / tên / MSSV; đơn cần giao sớm nhất lên đầu.
    /// </summary>
    [HttpGet]
    [Authorize(Policy = Policies.StaffOrAdmin)]
    public async Task<PagedResult<OrderSummaryDto>> ListForStaff([FromQuery] StaffOrdersQuery query, CancellationToken ct) =>
        await orders.ListForStaffAsync(query, ct);
}
