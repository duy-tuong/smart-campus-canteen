using CanteenApi.Common;
using CanteenApi.Data;
using CanteenApi.Dtos.Reviews;
using CanteenApi.Models;
using CanteenApi.Options;
using CanteenApi.Services.Notifications;
using CanteenApi.Services.Realtime;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace CanteenApi.Services.Reviews;

/// <summary>
/// Đánh giá món.
///  - Chỉ chủ đơn, đơn đã HOÀN THÀNH, món có trong đơn; viết/sửa trong N ngày (mặc định 7) sau khi nhận món.
///  - Mỗi món mỗi đơn một đánh giá (UNIQUE OrderId + FoodId).
///  - Điểm trung bình và số đánh giá của món được TÍNH LẠI TỪ ĐẦU bằng một câu UPDATE trên SQL Server
///    sau mỗi thay đổi (chỉ tính đánh giá không bị ẩn) — không cộng/trừ dần, nên nhiều người đánh giá
///    cùng lúc vẫn ra số đúng (có test 10 đánh giá song song).
/// </summary>
public sealed class ReviewService(
    CanteenDbContext db,
    NotificationService notifications,
    IRealtimePublisher realtime,
    IPublicUrlBuilder urls,
    IOptions<ReviewOptions> options,
    TimeProvider clock,
    ILogger<ReviewService> logger)
{
    private int WindowDays => options.Value.EditWindowDays;
    private DateTime Now => clock.GetUtcNow().UtcDateTime;

    // ============================ Sinh viên ============================

    /// <summary>Màn "Đánh giá đơn hàng": các món trong đơn kèm đánh giá của tôi.</summary>
    public async Task<OrderReviewsDto> GetOrderReviewsAsync(string orderId, string uid, CancellationToken ct)
    {
        var order = await FindOwnOrderAsync(orderId, uid, ct);
        var deadline = await ReviewDeadlineAsync(order, ct);

        var items = await db.OrderItems.AsNoTracking()
            .Where(i => i.OrderId == orderId && i.FoodId != null)
            .GroupBy(i => new { FoodId = i.FoodId!.Value, i.FoodName, i.Food!.ImageUrl })
            .Select(g => new { g.Key.FoodId, g.Key.FoodName, g.Key.ImageUrl, Quantity = g.Sum(i => i.Quantity) })
            .OrderBy(x => x.FoodName)
            .ToListAsync(ct);

        var mine = await ReviewsQuery().Where(r => r.OrderId == orderId).ToListAsync(ct);

        return new OrderReviewsDto(
            orderId,
            deadline is { } d && Now <= d,
            deadline,
            items.Select(i => new OrderReviewItemDto(
                i.FoodId, i.FoodName, urls.Build(i.ImageUrl), i.Quantity,
                mine.FirstOrDefault(r => r.FoodId == i.FoodId) is { } r ? ToDto(r, uid, isStaff: false, deadline) : null))
                .ToList());
    }

    public async Task<ReviewDto> CreateAsync(string orderId, string uid, CreateReviewRequest request, CancellationToken ct)
    {
        var order = await FindOwnOrderAsync(orderId, uid, ct);
        var deadline = await EnsureCanWriteAsync(order, ct);

        if (!await db.OrderItems.AnyAsync(i => i.OrderId == orderId && i.FoodId == request.FoodId, ct))
            throw new BusinessRuleException(ErrorCodes.ReviewNotAllowed, "Món này không có trong đơn hàng.");

        // Kiểm tra trước cho trường hợp thường gặp (bấm gửi 2 lần); UNIQUE(OrderId, FoodId) vẫn là chốt chặn cuối khi gửi song song.
        if (await db.Reviews.AnyAsync(r => r.OrderId == orderId && r.FoodId == request.FoodId, ct))
            throw new ConflictException(ErrorCodes.ReviewExists, "Bạn đã đánh giá món này trong đơn rồi. Hãy sửa đánh giá cũ.");

        var review = new Review
        {
            OrderId = orderId,
            FoodId = request.FoodId,
            UserId = uid,
            Rating = (byte)request.Rating,
            Comment = NormalizeComment(request.Comment),
        };

        try
        {
            await WithFoodLockAsync(request.FoodId, async () =>
            {
                db.Reviews.Add(review);
                await db.SaveChangesAsync(ct);
            }, ct);
        }
        catch (DbUpdateException ex) when (ex.InnerException is SqlException { Number: 2601 or 2627 })
        {
            throw new ConflictException(ErrorCodes.ReviewExists, "Bạn đã đánh giá món này trong đơn rồi. Hãy sửa đánh giá cũ.");
        }

        logger.LogInformation("Review {Id}: {Uid} rated food {FoodId} {Rating}★", review.Id, uid, review.FoodId, review.Rating);
        return await GetDtoAsync(review.Id, uid, isStaff: false, ct);
    }

    public async Task<ReviewDto> UpdateAsync(int id, string uid, UpdateReviewRequest request, CancellationToken ct)
    {
        var review = await FindOwnReviewAsync(id, uid, ct);
        if (review.IsHidden)
            throw new BusinessRuleException(ErrorCodes.ReviewHidden, "Đánh giá đã bị ẩn nên không thể sửa.");
        await EnsureCanWriteAsync(review.Order!, ct);

        await WithFoodLockAsync(review.FoodId, async () =>
        {
            review.Rating = (byte)request.Rating;
            review.Comment = NormalizeComment(request.Comment);
            await db.SaveChangesAsync(ct);
        }, ct);

        return await GetDtoAsync(id, uid, isStaff: false, ct);
    }

    /// <summary>Tác giả xóa đánh giá của mình (không giới hạn thời gian).</summary>
    public async Task DeleteAsync(int id, string uid, CancellationToken ct)
    {
        var review = await FindOwnReviewAsync(id, uid, ct);
        await WithFoodLockAsync(review.FoodId, async () =>
        {
            db.Reviews.Remove(review);
            await db.SaveChangesAsync(ct);
        }, ct);
    }

    public Task<PagedResult<ReviewDto>> ListMineAsync(string uid, PageQuery query, CancellationToken ct) =>
        ToPageAsync(ReviewsQuery().Where(r => r.UserId == uid).OrderByDescending(r => r.CreatedAt), query, uid, isStaff: false, ct);

    // ============================ Công khai ============================

    /// <summary>Đánh giá công khai của một món (không gồm đánh giá bị ẩn) kèm tổng quan và phân bố sao.</summary>
    public async Task<FoodReviewPageDto> ListForFoodAsync(int foodId, string viewerUid, FoodReviewQuery query, CancellationToken ct)
    {
        var food = await db.Foods.AsNoTracking()
            .Where(f => f.Id == foodId && !f.IsDeleted)
            .Select(f => new { f.AverageRating, f.RatingCount })
            .FirstOrDefaultAsync(ct)
            ?? throw new NotFoundException("Không tìm thấy món ăn.");

        var visible = ReviewsQuery().Where(r => r.FoodId == foodId && !r.IsHidden);

        var counts = await visible.GroupBy(r => r.Rating)
            .Select(g => new { Rating = g.Key, Count = g.Count() })
            .ToDictionaryAsync(x => x.Rating, x => x.Count, ct);
        var distribution = Enumerable.Range(1, 5).Reverse()
            .ToDictionary(star => star.ToString(), star => counts.GetValueOrDefault((byte)star));

        var filtered = query.Rating is { } rating ? visible.Where(r => r.Rating == rating) : visible;
        var sorted = query.Sort switch
        {
            "rating_desc" => filtered.OrderByDescending(r => r.Rating).ThenByDescending(r => r.CreatedAt),
            "rating_asc" => filtered.OrderBy(r => r.Rating).ThenByDescending(r => r.CreatedAt),
            _ => filtered.OrderByDescending(r => r.CreatedAt),
        };

        return new FoodReviewPageDto(
            new FoodReviewSummaryDto(foodId, food.AverageRating, food.RatingCount, distribution),
            await ToPageAsync(sorted, query, viewerUid, isStaff: false, ct));
    }

    // ============================ Quản lý (staff/admin) ============================

    public Task<PagedResult<ReviewDto>> ListForStaffAsync(AdminReviewQuery query, string staffUid, CancellationToken ct)
    {
        var reviews = ReviewsQuery();
        if (query.FoodId is { } foodId) reviews = reviews.Where(r => r.FoodId == foodId);
        if (query.Rating is { } rating) reviews = reviews.Where(r => r.Rating == rating);
        if (query.IsHidden is { } hidden) reviews = reviews.Where(r => r.IsHidden == hidden);
        if (query.HasReply is { } hasReply) reviews = reviews.Where(r => (r.StaffReply != null) == hasReply);
        if (!string.IsNullOrWhiteSpace(query.Q))
        {
            var term = query.Q.Trim();
            reviews = reviews.Where(r => r.Comment != null &&
                EF.Functions.Collate(r.Comment, SearchCollation.AccentInsensitive).Contains(term));
        }

        return ToPageAsync(reviews.OrderByDescending(r => r.CreatedAt), query, staffUid, isStaff: true, ct);
    }

    /// <summary>Ẩn (bắt buộc lý do) / hiện lại đánh giá; điểm trung bình của món được tính lại.</summary>
    public async Task<ReviewDto> SetVisibilityAsync(int id, bool isHidden, string? reason, string staffUid, CancellationToken ct)
    {
        var review = await db.Reviews.FirstOrDefaultAsync(r => r.Id == id, ct)
            ?? throw new NotFoundException("Không tìm thấy đánh giá.");

        var trimmed = string.IsNullOrWhiteSpace(reason) ? null : reason.Trim();
        if (isHidden && trimmed is null)
            throw new BadRequestException(ErrorCodes.ValidationError, "Vui lòng nêu lý do ẩn đánh giá.");

        await WithFoodLockAsync(review.FoodId, async () =>
        {
            review.IsHidden = isHidden;
            review.HiddenReason = isHidden ? trimmed : null;
            await db.SaveChangesAsync(ct);
        }, ct);

        logger.LogInformation("Review {Id} {Action} by {Staff}", id, isHidden ? "hidden" : "shown", staffUid);
        return await GetDtoAsync(id, staffUid, isStaff: true, ct);
    }

    /// <summary>Trả lời (hoặc sửa câu trả lời) đánh giá; tác giả nhận thông báo.</summary>
    public async Task<ReviewDto> ReplyAsync(int id, string reply, string staffUid, CancellationToken ct)
    {
        var review = await db.Reviews.Include(r => r.Food).FirstOrDefaultAsync(r => r.Id == id, ct)
            ?? throw new NotFoundException("Không tìm thấy đánh giá.");

        review.StaffReply = reply.Trim();
        review.RepliedAt = Now;
        review.RepliedByUserId = staffUid;
        var notification = notifications.ForReviewReply(review, review.Food!.Name);
        await db.SaveChangesAsync(ct);

        realtime.PublishNotification(notification.Id);
        return await GetDtoAsync(id, staffUid, isStaff: true, ct);
    }

    public async Task<ReviewDto> RemoveReplyAsync(int id, string staffUid, CancellationToken ct)
    {
        var review = await db.Reviews.FirstOrDefaultAsync(r => r.Id == id, ct)
            ?? throw new NotFoundException("Không tìm thấy đánh giá.");

        review.StaffReply = null;
        review.RepliedAt = null;
        review.RepliedByUserId = null;
        await db.SaveChangesAsync(ct);
        return await GetDtoAsync(id, staffUid, isStaff: true, ct);
    }

    // ============================ Điểm trung bình ============================

    /// <summary>
    /// Khóa dòng món (UPDLOCK) → thực hiện thay đổi → tính lại điểm, tất cả trong một transaction.
    /// Tính đúng đắn của điểm đến từ việc TÍNH LẠI TỪ ĐẦU; khóa là biện pháp phòng ngừa: xếp hàng các lần ghi
    /// vào cùng một món để tránh tranh chấp khóa giữa việc chèn đánh giá và câu UPDATE (thử bỏ khóa,
    /// test song song vẫn đạt — chi phí giữ khóa rất nhỏ nên vẫn giữ).
    /// </summary>
    private async Task WithFoodLockAsync(int foodId, Func<Task> change, CancellationToken ct)
    {
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        await db.Database.ExecuteSqlInterpolatedAsync($"SELECT Id FROM Foods WITH (UPDLOCK, ROWLOCK) WHERE Id = {foodId}", ct);
        await change();
        await RecalculateFoodRatingAsync(foodId, ct);
        await tx.CommitAsync(ct);
    }

    /// <summary>
    /// Một câu UPDATE: RatingCount = số đánh giá không bị ẩn, AverageRating = trung bình làm tròn 2 chữ số (0 nếu chưa có).
    /// </summary>
    public Task RecalculateFoodRatingAsync(int foodId, CancellationToken ct) =>
        RecalculateRatingsAsync(db.Foods.Where(f => f.Id == foodId), ct);

    /// <summary>Tính lại điểm của MỌI món bằng một câu UPDATE (dùng sau khi nhập dữ liệu hàng loạt).</summary>
    public Task RecalculateAllFoodRatingsAsync(CancellationToken ct) => RecalculateRatingsAsync(db.Foods, ct);

    private Task<int> RecalculateRatingsAsync(IQueryable<Food> foods, CancellationToken ct) =>
        foods.ExecuteUpdateAsync(s => s
            .SetProperty(f => f.RatingCount, f => db.Reviews.Count(r => r.FoodId == f.Id && !r.IsHidden))
            .SetProperty(f => f.AverageRating, f => Math.Round(
                db.Reviews.Where(r => r.FoodId == f.Id && !r.IsHidden).Average(r => (decimal?)r.Rating) ?? 0m, 2)), ct);

    // ============================ Hỗ trợ ============================

    private IQueryable<Review> ReviewsQuery() =>
        db.Reviews.AsNoTracking().Include(r => r.User).Include(r => r.Food).Include(r => r.Order);

    private async Task<Order> FindOwnOrderAsync(string orderId, string uid, CancellationToken ct) =>
        await db.Orders.AsNoTracking().FirstOrDefaultAsync(o => o.Id == orderId && o.UserId == uid, ct)
        ?? throw new NotFoundException("Không tìm thấy đơn hàng.");

    private async Task<Review> FindOwnReviewAsync(int id, string uid, CancellationToken ct) =>
        await db.Reviews.Include(r => r.Order).FirstOrDefaultAsync(r => r.Id == id && r.UserId == uid, ct)
        ?? throw new NotFoundException("Không tìm thấy đánh giá.");

    /// <summary>Hạn đánh giá = thời điểm hoàn thành đơn + N ngày; null nếu đơn chưa hoàn thành.</summary>
    private async Task<DateTime?> ReviewDeadlineAsync(Order order, CancellationToken ct)
    {
        if (order.Status != OrderStatus.Completed) return null;
        var completedAt = await db.OrderStatusHistory.AsNoTracking()
            .Where(h => h.OrderId == order.Id && h.ToStatus == OrderStatus.Completed)
            .Select(h => (DateTime?)h.ChangedAt)
            .MaxAsync(ct);
        return (completedAt ?? order.UpdatedAt).AddDays(WindowDays);
    }

    private async Task<DateTime> EnsureCanWriteAsync(Order order, CancellationToken ct)
    {
        if (order.Status != OrderStatus.Completed)
            throw new BusinessRuleException(ErrorCodes.ReviewNotAllowed, "Chỉ đánh giá được sau khi đã nhận món.");

        var deadline = (await ReviewDeadlineAsync(order, ct))!.Value;
        if (Now > deadline)
            throw new BusinessRuleException(ErrorCodes.ReviewWindowClosed,
                $"Đã quá {WindowDays} ngày kể từ khi nhận món, không thể đánh giá hoặc sửa đánh giá.");
        return deadline;
    }

    private async Task<ReviewDto> GetDtoAsync(int id, string viewerUid, bool isStaff, CancellationToken ct)
    {
        var review = await ReviewsQuery().FirstAsync(r => r.Id == id, ct);
        return ToDto(review, viewerUid, isStaff, await ReviewDeadlineAsync(review.Order!, ct));
    }

    private async Task<PagedResult<ReviewDto>> ToPageAsync(
        IQueryable<Review> query, PageQuery page, string viewerUid, bool isStaff, CancellationToken ct)
    {
        var result = await query.ToPagedResultAsync(page, ct);
        var items = new List<ReviewDto>(result.Items.Count);
        foreach (var r in result.Items)
        {
            var deadline = r.UserId == viewerUid ? await ReviewDeadlineAsync(r.Order!, ct) : null;
            items.Add(ToDto(r, viewerUid, isStaff, deadline));
        }
        return new PagedResult<ReviewDto>(items, result.Page, result.PageSize, result.TotalCount);
    }

    private ReviewDto ToDto(Review r, string viewerUid, bool isStaff, DateTime? deadline)
    {
        var isMine = r.UserId == viewerUid;
        return new ReviewDto(
            r.Id, r.FoodId, r.Food?.Name ?? "", r.OrderId, r.Rating, r.Comment,
            isStaff ? r.User?.FullName ?? "" : MaskName(r.User?.FullName),
            isMine,
            isMine && !r.IsHidden && deadline is { } d && Now <= d,
            r.IsHidden,
            isMine || isStaff ? r.HiddenReason : null,
            r.StaffReply, r.RepliedAt, r.CreatedAt, r.UpdatedAt);
    }

    /// <summary>Rút gọn tên khi hiển thị công khai: "Nguyễn Văn An" → "An N.".</summary>
    public static string MaskName(string? fullName)
    {
        var parts = (fullName ?? "").Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return parts.Length switch
        {
            0 => "Ẩn danh",
            1 => parts[0],
            _ => $"{parts[^1]} {char.ToUpperInvariant(parts[0][0])}.",
        };
    }

    private static string? NormalizeComment(string? comment) =>
        string.IsNullOrWhiteSpace(comment) ? null : comment.Trim();
}
