using CanteenApi.Common;
using CanteenApi.Data;
using CanteenApi.Dtos.Orders;
using CanteenApi.Models;
using Microsoft.EntityFrameworkCore;

namespace CanteenApi.Services.Ordering;

/// <summary>Kết quả kiểm tra voucher dùng nội bộ (kèm VoucherId để ghi vào đơn).</summary>
public sealed record VoucherEvaluation(VoucherCheckDto Check, int? VoucherId)
{
    public bool IsValid => Check.IsValid;
}

/// <summary>Nghiệp vụ mã giảm giá: kiểm tra điều kiện, tính tiền giảm, giữ/trả lượt dùng, quản lý (staff/admin).</summary>
public sealed class VoucherService(CanteenDbContext db, TimeProvider clock, ILogger<VoucherService> logger)
{
    // ============================ Kiểm tra & tính giảm ============================

    /// <summary>
    /// Kiểm tra voucher cho một đơn có tạm tính <paramref name="subtotal"/> của người dùng <paramref name="uid"/>.
    /// Không ném lỗi: trả kết quả kèm mã lỗi để màn Thanh toán hiển thị.
    /// </summary>
    public async Task<VoucherEvaluation> EvaluateAsync(string code, string uid, int subtotal, CancellationToken ct)
    {
        var normalized = NormalizeCode(code);
        var now = clock.GetUtcNow().UtcDateTime;

        var voucher = await db.Vouchers.AsNoTracking().FirstOrDefaultAsync(v => v.Code == normalized, ct);
        if (voucher is null || !voucher.IsActive)
            return Fail(normalized, ErrorCodes.VoucherInvalid, "Mã giảm giá không tồn tại hoặc đã ngừng áp dụng.");

        if (now < voucher.StartAt)
            return Fail(normalized, ErrorCodes.VoucherExpired,
                $"Mã chưa đến thời gian áp dụng (từ {ToVietnam(voucher.StartAt):HH:mm dd/MM/yyyy}).");
        if (now >= voucher.EndAt)
            return Fail(normalized, ErrorCodes.VoucherExpired, "Mã giảm giá đã hết hạn.");

        if (subtotal < voucher.MinOrderAmount)
            return Fail(normalized, ErrorCodes.VoucherMinOrder,
                $"Đơn tối thiểu {Money.Format(voucher.MinOrderAmount)} để dùng mã này (còn thiếu {Money.Format(voucher.MinOrderAmount - subtotal)}).");

        if (voucher.UsageLimit is { } limit && voucher.UsedCount >= limit)
            return Fail(normalized, ErrorCodes.VoucherExhausted, "Mã giảm giá đã hết lượt sử dụng.");

        if (voucher.PerUserLimit is { } perUser && await CountUserUsesAsync(voucher.Id, uid, ct) >= perUser)
            return Fail(normalized, ErrorCodes.VoucherUserLimit, $"Bạn đã dùng hết {perUser} lượt của mã này.");

        var discount = CalculateDiscount(voucher, subtotal);
        return new VoucherEvaluation(
            new VoucherCheckDto(normalized, true, discount, null, $"Áp dụng thành công: giảm {Money.Format(discount)}."),
            voucher.Id);
    }

    /// <summary>
    /// Tiền giảm:
    ///  - Percent: floor(subtotal × % / 100) làm tròn XUỐNG tới 100đ, không vượt MaxDiscount.
    ///  - Fixed: giá trị cố định.
    /// Luôn không vượt quá tạm tính (CHECK DiscountAmount ≤ Subtotal trong database).
    /// </summary>
    public static int CalculateDiscount(Voucher voucher, int subtotal)
    {
        var discount = voucher.DiscountType switch
        {
            DiscountType.Percent => (int)((long)subtotal * voucher.DiscountValue / 100 / 100 * 100),
            _ => voucher.DiscountValue,
        };

        if (voucher.MaxDiscount is { } max) discount = Math.Min(discount, max);
        return Math.Clamp(discount, 0, subtotal);
    }

    /// <summary>
    /// Giữ một lượt dùng bằng UPDATE nguyên tử có điều kiện:
    /// "UsedCount = UsedCount + 1 WHERE UsedCount &lt; UsageLimit". Nhiều người dùng cùng lúc cũng không vượt giới hạn.
    /// Trả false nếu mã vừa hết lượt.
    /// </summary>
    public async Task<bool> TryConsumeAsync(int voucherId, CancellationToken ct)
    {
        var affected = await db.Vouchers
            .Where(v => v.Id == voucherId && v.IsActive && (v.UsageLimit == null || v.UsedCount < v.UsageLimit))
            .ExecuteUpdateAsync(s => s.SetProperty(v => v.UsedCount, v => v.UsedCount + 1), ct);
        return affected == 1;
    }

    /// <summary>Trả lại một lượt dùng (khi đơn bị hủy).</summary>
    public Task ReleaseAsync(int voucherId, CancellationToken ct) =>
        db.Vouchers.Where(v => v.Id == voucherId && v.UsedCount > 0)
            .ExecuteUpdateAsync(s => s.SetProperty(v => v.UsedCount, v => v.UsedCount - 1), ct);

    // ============================ Sinh viên ============================

    /// <summary>Voucher tôi đang dùng được (đang hiệu lực, còn lượt chung và còn lượt của riêng tôi).</summary>
    public async Task<IReadOnlyList<AvailableVoucherDto>> ListAvailableAsync(string uid, CancellationToken ct)
    {
        var now = clock.GetUtcNow().UtcDateTime;

        var vouchers = await db.Vouchers.AsNoTracking()
            .Where(v => v.IsActive && v.StartAt <= now && v.EndAt > now &&
                        (v.UsageLimit == null || v.UsedCount < v.UsageLimit))
            .Select(v => new
            {
                Voucher = v,
                MyUses = v.Orders.Count(o => o.UserId == uid && o.Status != OrderStatus.Cancelled),
            })
            .ToListAsync(ct);

        return vouchers
            .Where(x => x.Voucher.PerUserLimit is null || x.MyUses < x.Voucher.PerUserLimit)
            .OrderBy(x => x.Voucher.EndAt)
            .Select(x => new AvailableVoucherDto(
                x.Voucher.Code, x.Voucher.Description, x.Voucher.DiscountType, x.Voucher.DiscountValue,
                x.Voucher.MaxDiscount, x.Voucher.MinOrderAmount, x.Voucher.EndAt,
                x.Voucher.PerUserLimit is { } limit ? limit - x.MyUses : null))
            .ToList();
    }

    // ============================ Quản lý (staff/admin) ============================

    public async Task<PagedResult<VoucherDto>> ListAsync(VoucherQuery query, CancellationToken ct)
    {
        var vouchers = db.Vouchers.AsNoTracking();
        if (!string.IsNullOrWhiteSpace(query.Q)) vouchers = vouchers.Where(v => v.Code.Contains(query.Q.Trim()));
        if (query.IsActive is { } active) vouchers = vouchers.Where(v => v.IsActive == active);

        return await vouchers
            .OrderByDescending(v => v.IsActive).ThenByDescending(v => v.CreatedAt)
            .Select(ToDtoExpression)
            .ToPagedResultAsync(query, ct);
    }

    public async Task<VoucherDto> GetAsync(int id, CancellationToken ct) =>
        await db.Vouchers.AsNoTracking().Where(v => v.Id == id).Select(ToDtoExpression).FirstOrDefaultAsync(ct)
        ?? throw new NotFoundException("Không tìm thấy voucher.");

    public async Task<VoucherDto> CreateAsync(SaveVoucherRequest request, CancellationToken ct)
    {
        var code = NormalizeCode(request.Code);
        if (await db.Vouchers.AnyAsync(v => v.Code == code, ct))
            throw new ConflictException(ErrorCodes.VoucherCodeTaken, $"Mã {code} đã tồn tại.");

        var voucher = new Voucher { Code = code };
        Apply(voucher, request);
        voucher.IsActive = request.IsActive ?? true;
        db.Vouchers.Add(voucher);
        await db.SaveChangesAsync(ct);

        logger.LogInformation("Created voucher {Code}", code);
        return await GetAsync(voucher.Id, ct);
    }

    /// <summary>
    /// Sửa voucher (bắt buộc rowVersion). Khi mã đã từng được dùng trong đơn thì KHÔNG đổi được mã
    /// và kiểu giảm (hóa đơn cũ tham chiếu theo mã); tổng lượt không được nhỏ hơn số lượt đã dùng.
    /// </summary>
    public async Task<VoucherDto> UpdateAsync(int id, SaveVoucherRequest request, CancellationToken ct)
    {
        var voucher = await db.Vouchers.FirstOrDefaultAsync(v => v.Id == id, ct)
            ?? throw new NotFoundException("Không tìm thấy voucher.");

        if (string.IsNullOrWhiteSpace(request.RowVersion))
            throw new BadRequestException(ErrorCodes.ValidationError, "Thiếu rowVersion (lấy từ chi tiết voucher).");
        SetExpectedRowVersion(voucher, request.RowVersion);

        var code = NormalizeCode(request.Code);
        var inUse = await db.Orders.AnyAsync(o => o.VoucherId == id, ct);
        if (inUse && (code != voucher.Code || request.DiscountType != voucher.DiscountType))
            throw new BusinessRuleException(ErrorCodes.VoucherInUse,
                "Mã đã được dùng trong đơn hàng: không thể đổi mã hoặc kiểu giảm. Hãy tạo mã mới.");

        if (code != voucher.Code && await db.Vouchers.AnyAsync(v => v.Code == code && v.Id != id, ct))
            throw new ConflictException(ErrorCodes.VoucherCodeTaken, $"Mã {code} đã tồn tại.");

        if (request.UsageLimit is { } limit && limit < voucher.UsedCount)
            throw new BusinessRuleException(ErrorCodes.ValidationError,
                $"Tổng lượt dùng không được nhỏ hơn số lượt đã dùng ({voucher.UsedCount}).");

        voucher.Code = code;
        Apply(voucher, request);
        voucher.IsActive = request.IsActive ?? voucher.IsActive;
        await db.SaveChangesAsync(ct);

        return await GetAsync(id, ct);
    }

    public async Task<VoucherDto> SetActiveAsync(int id, bool isActive, CancellationToken ct)
    {
        var voucher = await db.Vouchers.FirstOrDefaultAsync(v => v.Id == id, ct)
            ?? throw new NotFoundException("Không tìm thấy voucher.");
        voucher.IsActive = isActive;
        await db.SaveChangesAsync(ct);
        return await GetAsync(id, ct);
    }

    /// <summary>Chỉ xóa được voucher chưa từng dùng; đã dùng thì phải tắt (giữ lịch sử hóa đơn).</summary>
    public async Task DeleteAsync(int id, CancellationToken ct)
    {
        var voucher = await db.Vouchers.FirstOrDefaultAsync(v => v.Id == id, ct)
            ?? throw new NotFoundException("Không tìm thấy voucher.");

        if (await db.Orders.AnyAsync(o => o.VoucherId == id, ct))
            throw new ConflictException(ErrorCodes.VoucherInUse,
                "Mã đã được dùng trong đơn hàng nên không thể xóa. Hãy tắt mã thay vì xóa.");

        db.Vouchers.Remove(voucher);
        await db.SaveChangesAsync(ct);
    }

    // ============================ Hỗ trợ ============================

    public static string NormalizeCode(string code) => code.Trim().ToUpperInvariant();

    private Task<int> CountUserUsesAsync(int voucherId, string uid, CancellationToken ct) =>
        db.Orders.CountAsync(o => o.VoucherId == voucherId && o.UserId == uid && o.Status != OrderStatus.Cancelled, ct);

    private static VoucherEvaluation Fail(string code, string errorCode, string message) =>
        new(new VoucherCheckDto(code, false, 0, errorCode, message), null);

    private static DateTime ToVietnam(DateTime utc) => TimeZoneInfo.ConvertTimeFromUtc(utc, VietnamTime.Zone);

    private static void Apply(Voucher v, SaveVoucherRequest r)
    {
        v.Description = r.Description.Trim();
        v.DiscountType = r.DiscountType!.Value;
        v.DiscountValue = r.DiscountValue;
        v.MaxDiscount = r.DiscountType == DiscountType.Percent ? r.MaxDiscount : null;
        v.MinOrderAmount = r.MinOrderAmount;
        v.StartAt = r.StartAt!.Value.UtcDateTime;
        v.EndAt = r.EndAt!.Value.UtcDateTime;
        v.UsageLimit = r.UsageLimit;
        v.PerUserLimit = r.PerUserLimit;
    }

    private void SetExpectedRowVersion(Voucher voucher, string rowVersion)
    {
        try
        {
            db.Entry(voucher).Property(v => v.RowVersion).OriginalValue = Convert.FromBase64String(rowVersion);
        }
        catch (FormatException)
        {
            throw new BadRequestException(ErrorCodes.ValidationError, "rowVersion không hợp lệ.");
        }
    }

    private static readonly System.Linq.Expressions.Expression<Func<Voucher, VoucherDto>> ToDtoExpression = v =>
        new VoucherDto(
            v.Id, v.Code, v.Description, v.DiscountType, v.DiscountValue, v.MaxDiscount, v.MinOrderAmount,
            v.StartAt, v.EndAt, v.UsageLimit, v.UsedCount, v.PerUserLimit, v.IsActive,
            v.Orders.Count(), Convert.ToBase64String(v.RowVersion), v.CreatedAt, v.UpdatedAt);
}
