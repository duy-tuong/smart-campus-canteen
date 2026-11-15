using CanteenApi.Auth;
using CanteenApi.Common;
using CanteenApi.Dtos.Reviews;
using CanteenApi.Services.Reviews;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CanteenApi.Controllers;

/// <summary>Đánh giá món của sinh viên.</summary>
[ApiController]
[Tags("Đánh giá")]
public class ReviewsController(ReviewService reviews, ICurrentUser me) : ControllerBase
{
    /// <summary>Đánh giá công khai của một món (không gồm đánh giá bị ẩn) kèm điểm trung bình và phân bố sao.</summary>
    [HttpGet("api/foods/{foodId:int}/reviews")]
    public async Task<FoodReviewPageDto> ListForFood(int foodId, [FromQuery] FoodReviewQuery query, CancellationToken ct) =>
        await reviews.ListForFoodAsync(foodId, me.Uid, query, ct);

    /// <summary>Màn "Đánh giá đơn hàng": các món trong đơn của tôi kèm đánh giá đã viết và hạn đánh giá.</summary>
    [HttpGet("api/orders/{orderId}/reviews")]
    public async Task<OrderReviewsDto> ListForOrder(string orderId, CancellationToken ct) =>
        await reviews.GetOrderReviewsAsync(orderId, me.Uid, ct);

    /// <summary>Đánh giá một món trong đơn đã hoàn thành (trong 7 ngày sau khi nhận món).</summary>
    /// <response code="409">REVIEW_EXISTS — đã đánh giá món này trong đơn.</response>
    /// <response code="422">REVIEW_NOT_ALLOWED (đơn chưa hoàn thành / món không có trong đơn), REVIEW_WINDOW_CLOSED.</response>
    [HttpPost("api/orders/{orderId}/reviews")]
    [ProducesResponseType<ReviewDto>(StatusCodes.Status201Created)]
    public async Task<IActionResult> Create(string orderId, [FromBody] CreateReviewRequest request, CancellationToken ct)
    {
        var review = await reviews.CreateAsync(orderId, me.Uid, request, ct);
        return Created($"/api/reviews/{review.Id}", review);
    }

    /// <summary>Sửa đánh giá của tôi (trong hạn, chưa bị ẩn).</summary>
    [HttpPut("api/reviews/{id:int}")]
    public async Task<ReviewDto> Update(int id, [FromBody] UpdateReviewRequest request, CancellationToken ct) =>
        await reviews.UpdateAsync(id, me.Uid, request, ct);

    /// <summary>Xóa đánh giá của tôi.</summary>
    [HttpDelete("api/reviews/{id:int}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        await reviews.DeleteAsync(id, me.Uid, ct);
        return NoContent();
    }

    /// <summary>Đánh giá của tôi (kể cả bị ẩn, kèm lý do), mới nhất trước.</summary>
    [HttpGet("api/users/me/reviews")]
    public async Task<PagedResult<ReviewDto>> ListMine([FromQuery] PageQuery query, CancellationToken ct) =>
        await reviews.ListMineAsync(me.Uid, query, ct);
}

/// <summary>Quản lý đánh giá: ẩn đánh giá vi phạm, trả lời khách (staff/admin).</summary>
[ApiController]
[Route("api/admin/reviews")]
[Authorize(Policy = Policies.StaffOrAdmin)]
[Tags("Quản lý đánh giá")]
public class AdminReviewsController(ReviewService reviews, ICurrentUser me) : ControllerBase
{
    /// <summary>Danh sách đánh giá: lọc theo món, số sao, đã ẩn, đã trả lời; tìm nội dung không dấu.</summary>
    [HttpGet]
    public async Task<PagedResult<ReviewDto>> List([FromQuery] AdminReviewQuery query, CancellationToken ct) =>
        await reviews.ListForStaffAsync(query, me.Uid, ct);

    /// <summary>Ẩn (bắt buộc lý do) / hiện lại đánh giá. Điểm trung bình của món được tính lại ngay.</summary>
    [HttpPatch("{id:int}/visibility")]
    public async Task<ReviewDto> SetVisibility(int id, [FromBody] ReviewVisibilityRequest request, CancellationToken ct) =>
        await reviews.SetVisibilityAsync(id, request.IsHidden!.Value, request.Reason, me.Uid, ct);

    /// <summary>Trả lời (hoặc sửa câu trả lời) đánh giá. Tác giả nhận thông báo.</summary>
    [HttpPut("{id:int}/reply")]
    public async Task<ReviewDto> Reply(int id, [FromBody] ReviewReplyRequest request, CancellationToken ct) =>
        await reviews.ReplyAsync(id, request.Reply, me.Uid, ct);

    /// <summary>Gỡ câu trả lời.</summary>
    [HttpDelete("{id:int}/reply")]
    public async Task<ReviewDto> RemoveReply(int id, CancellationToken ct) =>
        await reviews.RemoveReplyAsync(id, me.Uid, ct);
}
