using CanteenApi.Auth;
using CanteenApi.Dtos.Menu;
using CanteenApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CanteenApi.Controllers;

/// <summary>Danh mục món ăn. Đọc: mọi người dùng; thêm/sửa/xóa: staff hoặc admin.</summary>
[ApiController]
[Route("api/categories")]
[Tags("Thực đơn — Danh mục")]
public class CategoriesController(CategoryService categories, ICurrentUser me) : ControllerBase
{
    /// <summary>Danh sách danh mục (sắp theo thứ tự hiển thị).</summary>
    /// <param name="includeInactive">Chỉ có tác dụng với staff/admin: hiện cả danh mục đang ẩn.</param>
    [HttpGet]
    public async Task<IReadOnlyList<CategoryDto>> List([FromQuery] bool includeInactive, CancellationToken ct) =>
        await categories.ListAsync(includeInactive && me.IsStaffOrAdmin, ct);

    /// <summary>Chi tiết một danh mục.</summary>
    [HttpGet("{id:int}")]
    [ProducesResponseType<CategoryDto>(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<CategoryDto> Get(int id, CancellationToken ct) =>
        await categories.GetAsync(id, me.IsStaffOrAdmin, ct);

    /// <summary>Tạo danh mục.</summary>
    /// <response code="409">CATEGORY_NAME_TAKEN — trùng tên (không phân biệt dấu).</response>
    [HttpPost]
    [Authorize(Policy = Policies.StaffOrAdmin)]
    [ProducesResponseType<CategoryDto>(StatusCodes.Status201Created)]
    public async Task<IActionResult> Create([FromBody] SaveCategoryRequest request, CancellationToken ct)
    {
        var created = await categories.CreateAsync(request, ct);
        return CreatedAtAction(nameof(Get), new { id = created.Id }, created);
    }

    /// <summary>Sửa danh mục (gồm cả ẩn/hiện qua isActive).</summary>
    [HttpPut("{id:int}")]
    [Authorize(Policy = Policies.StaffOrAdmin)]
    public async Task<CategoryDto> Update(int id, [FromBody] SaveCategoryRequest request, CancellationToken ct) =>
        await categories.UpdateAsync(id, request, ct);

    /// <summary>Sắp xếp lại thứ tự hiển thị nhiều danh mục.</summary>
    [HttpPut("order")]
    [Authorize(Policy = Policies.StaffOrAdmin)]
    public async Task<IReadOnlyList<CategoryDto>> Reorder([FromBody] ReorderCategoriesRequest request, CancellationToken ct) =>
        await categories.ReorderAsync(request, ct);

    /// <summary>Xóa (mềm) danh mục.</summary>
    /// <response code="409">CATEGORY_NOT_EMPTY — danh mục còn món.</response>
    [HttpDelete("{id:int}")]
    [Authorize(Policy = Policies.StaffOrAdmin)]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        await categories.DeleteAsync(id, ct);
        return NoContent();
    }
}
