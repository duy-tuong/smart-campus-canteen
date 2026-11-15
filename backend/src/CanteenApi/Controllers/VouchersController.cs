using CanteenApi.Auth;
using CanteenApi.Common;
using CanteenApi.Dtos.Orders;
using CanteenApi.Services.Ordering;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CanteenApi.Controllers;

/// <summary>Mã giảm giá dành cho sinh viên.</summary>
[ApiController]
[Route("api/vouchers")]
[Tags("Voucher")]
public class VouchersController(VoucherService vouchers, ICurrentUser me) : ControllerBase
{
    /// <summary>Voucher tôi đang dùng được (còn hiệu lực, còn lượt chung và lượt của riêng tôi), sắp hết hạn trước.</summary>
    [HttpGet("available")]
    public async Task<IReadOnlyList<AvailableVoucherDto>> Available(CancellationToken ct) =>
        await vouchers.ListAvailableAsync(me.Uid, ct);
}

/// <summary>Quản lý mã giảm giá (staff/admin).</summary>
[ApiController]
[Route("api/admin/vouchers")]
[Authorize(Policy = Policies.StaffOrAdmin)]
[Tags("Quản lý voucher")]
public class AdminVouchersController(VoucherService vouchers) : ControllerBase
{
    /// <summary>Danh sách voucher (tìm theo mã, lọc trạng thái, phân trang) kèm số lượt đã dùng.</summary>
    [HttpGet]
    public async Task<PagedResult<VoucherDto>> List([FromQuery] VoucherQuery query, CancellationToken ct) =>
        await vouchers.ListAsync(query, ct);

    [HttpGet("{id:int}")]
    [ProducesResponseType<VoucherDto>(StatusCodes.Status200OK)]
    public async Task<VoucherDto> Get(int id, CancellationToken ct) => await vouchers.GetAsync(id, ct);

    /// <summary>Tạo voucher. Mã tự viết hoa.</summary>
    /// <response code="409">VOUCHER_CODE_TAKEN</response>
    [HttpPost]
    [ProducesResponseType<VoucherDto>(StatusCodes.Status201Created)]
    public async Task<IActionResult> Create([FromBody] SaveVoucherRequest request, CancellationToken ct)
    {
        var created = await vouchers.CreateAsync(request, ct);
        return CreatedAtAction(nameof(Get), new { id = created.Id }, created);
    }

    /// <summary>Sửa voucher (bắt buộc rowVersion). Mã đã dùng thì không đổi được mã/kiểu giảm.</summary>
    /// <response code="409">CONCURRENCY_CONFLICT / VOUCHER_CODE_TAKEN</response>
    /// <response code="422">VOUCHER_IN_USE</response>
    [HttpPut("{id:int}")]
    public async Task<VoucherDto> Update(int id, [FromBody] SaveVoucherRequest request, CancellationToken ct) =>
        await vouchers.UpdateAsync(id, request, ct);

    /// <summary>Bật / tắt voucher.</summary>
    [HttpPatch("{id:int}/status")]
    public async Task<VoucherDto> SetStatus(int id, [FromBody] UpdateVoucherStatusRequest request, CancellationToken ct) =>
        await vouchers.SetActiveAsync(id, request.IsActive!.Value, ct);

    /// <summary>Xóa voucher chưa từng được dùng.</summary>
    /// <response code="409">VOUCHER_IN_USE — đã có đơn dùng mã này, hãy tắt thay vì xóa.</response>
    [HttpDelete("{id:int}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        await vouchers.DeleteAsync(id, ct);
        return NoContent();
    }
}
