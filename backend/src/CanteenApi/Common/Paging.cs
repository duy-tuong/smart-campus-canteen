using System.ComponentModel.DataAnnotations;
using Microsoft.EntityFrameworkCore;

namespace CanteenApi.Common;

/// <summary>Tham số phân trang chung cho các API danh sách (?page=1&amp;pageSize=20).</summary>
public class PageQuery
{
    public const int MaxPageSize = 50;

    [Range(1, int.MaxValue, ErrorMessage = "Số trang phải từ 1 trở lên.")]
    public int Page { get; set; } = 1;

    [Range(1, MaxPageSize, ErrorMessage = "Số phần tử mỗi trang phải từ 1 đến 50.")]
    public int PageSize { get; set; } = 20;
}

/// <summary>Kết quả một trang dữ liệu.</summary>
public sealed record PagedResult<T>(IReadOnlyList<T> Items, int Page, int PageSize, int TotalCount)
{
    public int TotalPages => TotalCount == 0 ? 0 : (int)Math.Ceiling(TotalCount / (double)PageSize);
    public bool HasNext => Page < TotalPages;
}

public static class PagingExtensions
{
    /// <summary>Đếm tổng số bản ghi rồi lấy đúng một trang (2 truy vấn SQL: COUNT và OFFSET/FETCH).</summary>
    public static async Task<PagedResult<T>> ToPagedResultAsync<T>(
        this IQueryable<T> query, PageQuery page, CancellationToken ct = default)
    {
        var total = await query.CountAsync(ct);
        var items = await query
            .Skip((page.Page - 1) * page.PageSize)
            .Take(page.PageSize)
            .ToListAsync(ct);
        return new PagedResult<T>(items, page.Page, page.PageSize, total);
    }
}
