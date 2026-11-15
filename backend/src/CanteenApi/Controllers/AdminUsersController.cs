using CanteenApi.Auth;
using CanteenApi.Common;
using CanteenApi.Dtos.Users;
using CanteenApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CanteenApi.Controllers;

/// <summary>Quản trị tài khoản người dùng (chỉ admin).</summary>
[ApiController]
[Route("api/admin/users")]
[Authorize(Policy = Policies.AdminOnly)]
[Tags("Quản trị người dùng")]
public class AdminUsersController(UserService users, ICurrentUser me) : ControllerBase
{
    /// <summary>Danh sách người dùng: tìm kiếm (không dấu), lọc theo vai trò/trạng thái, phân trang.</summary>
    [HttpGet]
    [ProducesResponseType<PagedResult<AdminUserListItemDto>>(StatusCodes.Status200OK)]
    public async Task<PagedResult<AdminUserListItemDto>> List([FromQuery] AdminUserQuery query, CancellationToken ct) =>
        await users.ListAsync(query, ct);

    /// <summary>Chi tiết một người dùng kèm thống kê đơn hàng.</summary>
    [HttpGet("{id}")]
    [ProducesResponseType<AdminUserDetailDto>(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<AdminUserDetailDto> Get(string id, CancellationToken ct) =>
        await users.GetDetailAsync(id, ct);

    /// <summary>Đổi vai trò (student / staff / admin). Có hiệu lực ngay.</summary>
    /// <response code="403">CANNOT_MODIFY_SELF — không tự đổi vai trò của mình.</response>
    [HttpPatch("{id}/role")]
    [ProducesResponseType<AdminUserDetailDto>(StatusCodes.Status200OK)]
    public async Task<AdminUserDetailDto> ChangeRole(string id, [FromBody] UpdateRoleRequest request, CancellationToken ct) =>
        await users.ChangeRoleAsync(me.Uid, id, request.Role!.Value, ct);

    /// <summary>Khóa / mở tài khoản (khóa cả đăng nhập trên Firebase). Có hiệu lực ngay.</summary>
    /// <response code="403">CANNOT_MODIFY_SELF — không tự khóa tài khoản của mình.</response>
    [HttpPatch("{id}/status")]
    [ProducesResponseType<AdminUserDetailDto>(StatusCodes.Status200OK)]
    public async Task<AdminUserDetailDto> ChangeStatus(string id, [FromBody] UpdateStatusRequest request, CancellationToken ct) =>
        await users.ChangeStatusAsync(me.Uid, id, request.IsActive!.Value, ct);
}
