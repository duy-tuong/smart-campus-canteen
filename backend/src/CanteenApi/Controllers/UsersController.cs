using CanteenApi.Auth;
using CanteenApi.Common;
using CanteenApi.Dtos.Menu;
using CanteenApi.Dtos.Users;
using CanteenApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CanteenApi.Controllers;

/// <summary>Hồ sơ của người dùng đang đăng nhập.</summary>
[ApiController]
[Route("api/users")]
[Tags("Người dùng")]
public class UsersController(UserService users, ICurrentUser me) : ControllerBase
{
    /// <summary>Lấy hồ sơ của tôi (đồng thời ghi nhận thời điểm đăng nhập).</summary>
    /// <response code="404">PROFILE_NOT_FOUND — đã đăng ký Firebase nhưng chưa tạo hồ sơ.</response>
    /// <response code="403">ACCOUNT_LOCKED — tài khoản bị khóa.</response>
    [HttpGet("me")]
    [Authorize(Policy = Policies.SignedIn)]
    [ProducesResponseType<UserProfileDto>(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<UserProfileDto> GetMe(CancellationToken ct) =>
        await users.GetMeAsync(me.Uid, ct);

    /// <summary>Tạo hồ sơ sinh viên sau khi đăng ký tài khoản Firebase.</summary>
    /// <remarks>Email lấy từ token. Gọi lại khi đã có hồ sơ sẽ trả 200 với hồ sơ hiện có.</remarks>
    /// <response code="201">Đã tạo hồ sơ.</response>
    /// <response code="200">Hồ sơ đã tồn tại từ trước.</response>
    /// <response code="409">STUDENT_CODE_TAKEN — mã số sinh viên đã có người dùng.</response>
    [HttpPost("me")]
    [Authorize(Policy = Policies.SignedIn)]
    [ProducesResponseType<UserProfileDto>(StatusCodes.Status201Created)]
    [ProducesResponseType<UserProfileDto>(StatusCodes.Status200OK)]
    public async Task<IActionResult> CreateMe([FromBody] CreateProfileRequest request, CancellationToken ct)
    {
        var (profile, created) = await users.CreateMeAsync(me.Uid, me.Email, request, ct);
        return created ? CreatedAtAction(nameof(GetMe), null, profile) : Ok(profile);
    }

    /// <summary>Cập nhật hồ sơ của tôi.</summary>
    /// <response code="422">STUDENT_CODE_LOCKED — không được đổi mã số sinh viên đã có.</response>
    [HttpPut("me")]
    [ProducesResponseType<UserProfileDto>(StatusCodes.Status200OK)]
    public async Task<UserProfileDto> UpdateMe([FromBody] UpdateProfileRequest request, CancellationToken ct) =>
        await users.UpdateMeAsync(me.Uid, request, ct);

    /// <summary>Tải lên ảnh đại diện (JPEG/PNG/WebP, tối đa 2 MB).</summary>
    [HttpPost("me/avatar")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(3 * 1024 * 1024)]
    [ProducesResponseType<UserProfileDto>(StatusCodes.Status200OK)]
    public async Task<UserProfileDto> UploadAvatar(IFormFile file, CancellationToken ct) =>
        await users.UpdateAvatarAsync(me.Uid, file, ct);

    /// <summary>Món yêu thích của tôi (mới thêm trước).</summary>
    [HttpGet("me/favorites")]
    public async Task<PagedResult<FoodSummaryDto>> GetFavorites(
        [FromQuery] PageQuery query, [FromServices] FoodService foods, CancellationToken ct) =>
        await foods.ListFavoritesAsync(me.Uid, query, ct);

    /// <summary>Gỡ ảnh đại diện.</summary>
    [HttpDelete("me/avatar")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> RemoveAvatar(CancellationToken ct)
    {
        await users.RemoveAvatarAsync(me.Uid, ct);
        return NoContent();
    }
}
