using CanteenApi.Auth;
using CanteenApi.Common;
using CanteenApi.Dtos.Menu;
using CanteenApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CanteenApi.Controllers;

/// <summary>Món ăn. Đọc + yêu thích: mọi người dùng; thêm/sửa/xóa: staff hoặc admin.</summary>
[ApiController]
[Route("api/foods")]
[Tags("Thực đơn — Món ăn")]
public class FoodsController(FoodService foods, ICurrentUser me) : ControllerBase
{
    /// <summary>Danh sách món: lọc theo danh mục/giá, tìm không dấu, sắp xếp, phân trang.</summary>
    [HttpGet]
    public async Task<PagedResult<FoodSummaryDto>> List([FromQuery] FoodQuery query, CancellationToken ct) =>
        await foods.ListAsync(query, me.Uid, me.IsStaffOrAdmin, ct);

    /// <summary>Chi tiết món kèm nhóm tùy chọn (size, topping...) và rowVersion.</summary>
    [HttpGet("{id:int}")]
    [ProducesResponseType<FoodDetailDto>(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<FoodDetailDto> Get(int id, CancellationToken ct) =>
        await foods.GetDetailAsync(id, me.Uid, me.IsStaffOrAdmin, ct);

    /// <summary>Tạo món (có thể kèm luôn các nhóm tùy chọn).</summary>
    /// <response code="409">FOOD_NAME_TAKEN — danh mục đã có món cùng tên.</response>
    /// <response code="422">INVALID_CATEGORY / INVALID_OPTIONS.</response>
    [HttpPost]
    [Authorize(Policy = Policies.StaffOrAdmin)]
    [ProducesResponseType<FoodDetailDto>(StatusCodes.Status201Created)]
    public async Task<IActionResult> Create([FromBody] CreateFoodRequest request, CancellationToken ct)
    {
        var id = await foods.CreateAsync(request, ct);
        var created = await foods.GetDetailAsync(id, me.Uid, isStaff: true, ct);
        return CreatedAtAction(nameof(Get), new { id }, created);
    }

    /// <summary>Sửa thông tin món. Bắt buộc gửi rowVersion lấy từ chi tiết món.</summary>
    /// <response code="409">CONCURRENCY_CONFLICT — món đã được người khác sửa; tải lại rồi thử lại.</response>
    [HttpPut("{id:int}")]
    [Authorize(Policy = Policies.StaffOrAdmin)]
    public async Task<FoodDetailDto> Update(int id, [FromBody] UpdateFoodRequest request, CancellationToken ct)
    {
        await foods.UpdateAsync(id, request, ct);
        return await foods.GetDetailAsync(id, me.Uid, isStaff: true, ct);
    }

    /// <summary>Thay toàn bộ nhóm tùy chọn của món (danh sách rỗng = bỏ hết tùy chọn).</summary>
    /// <response code="422">INVALID_OPTIONS — cấu hình tùy chọn không hợp lệ.</response>
    [HttpPut("{id:int}/option-groups")]
    [Authorize(Policy = Policies.StaffOrAdmin)]
    public async Task<FoodDetailDto> ReplaceOptionGroups(int id, [FromBody] ReplaceOptionGroupsRequest request, CancellationToken ct)
    {
        await foods.ReplaceOptionGroupsAsync(id, request, ct);
        return await foods.GetDetailAsync(id, me.Uid, isStaff: true, ct);
    }

    /// <summary>Bật/tắt "hết món".</summary>
    [HttpPatch("{id:int}/availability")]
    [Authorize(Policy = Policies.StaffOrAdmin)]
    public async Task<FoodDetailDto> SetAvailability(int id, [FromBody] UpdateAvailabilityRequest request, CancellationToken ct)
    {
        await foods.SetAvailabilityAsync(id, request.IsAvailable!.Value, ct);
        return await foods.GetDetailAsync(id, me.Uid, isStaff: true, ct);
    }

    /// <summary>Tải lên ảnh món (JPEG/PNG/WebP, tối đa 5 MB).</summary>
    [HttpPost("{id:int}/image")]
    [Authorize(Policy = Policies.StaffOrAdmin)]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(6 * 1024 * 1024)]
    public async Task<FoodDetailDto> UploadImage(int id, IFormFile file, CancellationToken ct)
    {
        await foods.UpdateImageAsync(id, file, ct);
        return await foods.GetDetailAsync(id, me.Uid, isStaff: true, ct);
    }

    /// <summary>Xóa (mềm) món: không còn hiển thị nhưng hóa đơn/thống kê cũ vẫn giữ nguyên.</summary>
    [HttpDelete("{id:int}")]
    [Authorize(Policy = Policies.StaffOrAdmin)]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        await foods.DeleteAsync(id, ct);
        return NoContent();
    }

    /// <summary>Thêm món vào yêu thích (gọi lại nhiều lần vẫn an toàn).</summary>
    [HttpPut("{id:int}/favorite")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> AddFavorite(int id, CancellationToken ct)
    {
        await foods.AddFavoriteAsync(me.Uid, id, ct);
        return NoContent();
    }

    /// <summary>Bỏ món khỏi yêu thích.</summary>
    [HttpDelete("{id:int}/favorite")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> RemoveFavorite(int id, CancellationToken ct)
    {
        await foods.RemoveFavoriteAsync(me.Uid, id, ct);
        return NoContent();
    }
}
