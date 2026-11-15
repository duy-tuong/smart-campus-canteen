using CanteenApi.Common;
using CanteenApi.Data;
using CanteenApi.Dtos.Orders;
using CanteenApi.Models;
using CanteenApi.Options;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace CanteenApi.Services.Ordering;

/// <summary>Một dòng đã tính giá, kèm bản chụp dữ liệu để ghi vào OrderItems/OrderItemOptions.</summary>
public sealed record PricedLine(
    int Index, int FoodId, string FoodName, string? ImagePath, int UnitPrice, int OptionsPrice,
    int Quantity, int LineTotal, string? Note, int PrepTimeMinutes, IReadOnlyList<PricedOptionDto> Options);

/// <summary>Kết quả tính giá giỏ hàng.</summary>
public sealed record PricingResult(
    IReadOnlyList<PricedLine> Lines,
    IReadOnlyList<LineErrorDto> Errors,
    int Subtotal,
    VoucherEvaluation? Voucher,
    int DiscountAmount)
{
    public int TotalAmount => Subtotal - DiscountAmount;
    public int TotalItems => Lines.Sum(l => l.Quantity);
    public bool CanOrder => Errors.Count == 0 && Lines.Count > 0;
}

/// <summary>
/// Bộ tính giá dùng chung cho BÁO GIÁ (màn Thanh toán) và ĐẶT MÓN.
///
/// Nguyên tắc: client chỉ gửi foodId, số lượng, optionId — mọi giá đều lấy từ database,
/// nên sửa request (ví dụ đổi giá trên app) không thể làm giảm tiền phải trả.
///
/// Kiểm tra theo từng dòng (lỗi trả về theo dòng để app tô đỏ đúng món):
///  - món còn trong thực đơn và đang bán (ITEM_UNAVAILABLE)
///  - tùy chọn thuộc đúng món, đang có, không trùng, đúng min/max từng nhóm (OPTION_INVALID)
///  - đủ suất hôm nay, cộng dồn nếu cùng món ở nhiều dòng (ITEM_SOLD_OUT)
/// </summary>
public sealed class OrderPricingService(
    CanteenDbContext db,
    VoucherService vouchers,
    IOptions<CanteenOptions> options,
    TimeProvider clock)
{
    public async Task<PricingResult> PriceAsync(
        IReadOnlyList<CartLineRequest> items, string? voucherCode, string uid, CancellationToken ct)
    {
        if (items.Count > options.Value.MaxLinesPerOrder)
            throw new BadRequestException(ErrorCodes.ValidationError,
                $"Mỗi đơn tối đa {options.Value.MaxLinesPerOrder} dòng món.");

        var foodIds = items.Select(i => i.FoodId).Distinct().ToList();
        var foods = await db.Foods.AsNoTracking()
            .Where(f => foodIds.Contains(f.Id) && !f.IsDeleted && !f.Category!.IsDeleted && f.Category.IsActive)
            .Include(f => f.OptionGroups).ThenInclude(g => g.Options)
            .AsSplitQuery()
            .ToDictionaryAsync(f => f.Id, ct);

        var errors = new List<LineErrorDto>();
        var lines = new List<PricedLine>();

        for (var index = 0; index < items.Count; index++)
        {
            var item = items[index];
            if (!foods.TryGetValue(item.FoodId, out var food))
            {
                errors.Add(new LineErrorDto(index, item.FoodId, ErrorCodes.ItemUnavailable, "Món không còn trong thực đơn."));
                continue;
            }
            if (!food.IsAvailable)
            {
                errors.Add(new LineErrorDto(index, food.Id, ErrorCodes.ItemUnavailable, $"{food.Name} đang tạm hết."));
                continue;
            }

            var (selected, optionError) = ResolveOptions(food, item.OptionIds ?? []);
            if (optionError is not null)
            {
                errors.Add(new LineErrorDto(index, food.Id, ErrorCodes.OptionInvalid, $"{food.Name}: {optionError}"));
                continue;
            }

            var optionsPrice = selected.Sum(o => o.ExtraPrice);
            lines.Add(new PricedLine(
                index, food.Id, food.Name, food.ImageUrl, food.Price, optionsPrice, item.Quantity,
                (food.Price + optionsPrice) * item.Quantity,
                string.IsNullOrWhiteSpace(item.Note) ? null : item.Note.Trim(),
                food.PrepTimeMinutes, selected));
        }

        await CheckDailyLimitsAsync(foods, lines, errors, ct);

        var validLines = lines.Where(l => errors.All(e => e.Index != l.Index)).ToList();
        var subtotal = validLines.Sum(l => l.LineTotal);

        VoucherEvaluation? voucher = null;
        if (!string.IsNullOrWhiteSpace(voucherCode))
            voucher = await vouchers.EvaluateAsync(voucherCode, uid, subtotal, ct);

        return new PricingResult(
            validLines, errors.OrderBy(e => e.Index).ToList(), subtotal, voucher,
            voucher is { IsValid: true } ? voucher.Check.Discount : 0);
    }

    /// <summary>Kiểm tra và quy đổi optionId → bản chụp (tên nhóm, tên tùy chọn, giá).</summary>
    private static (IReadOnlyList<PricedOptionDto> Selected, string? Error) ResolveOptions(Food food, List<int> optionIds)
    {
        if (optionIds.Distinct().Count() != optionIds.Count) return ([], "chọn trùng tùy chọn.");

        var lookup = food.OptionGroups
            .SelectMany(g => g.Options.Select(o => (Group: g, Option: o)))
            .ToDictionary(x => x.Option.Id);

        var selected = new List<(FoodOptionGroup Group, FoodOption Option)>();
        foreach (var id in optionIds)
        {
            if (!lookup.TryGetValue(id, out var pair)) return ([], "tùy chọn không thuộc món này.");
            if (!pair.Option.IsAvailable) return ([], $"tùy chọn \"{pair.Option.Name}\" đang tạm hết.");
            selected.Add(pair);
        }

        foreach (var group in food.OptionGroups.OrderBy(g => g.SortOrder))
        {
            var count = selected.Count(s => s.Group.Id == group.Id);
            if (count < group.MinSelect)
                return ([], group.MinSelect == 1
                    ? $"vui lòng chọn {group.Name}."
                    : $"vui lòng chọn ít nhất {group.MinSelect} {group.Name}.");
            if (count > group.MaxSelect)
                return ([], $"chỉ được chọn tối đa {group.MaxSelect} {group.Name}.");
        }

        return (selected
            .OrderBy(s => s.Group.SortOrder).ThenBy(s => s.Option.SortOrder)
            .Select(s => new PricedOptionDto(s.Option.Id, s.Group.Name, s.Option.Name, s.Option.ExtraPrice))
            .ToList(), null);
    }

    /// <summary>Cộng dồn số lượng theo món (nhiều dòng cùng món, khác tùy chọn) rồi so với số suất còn lại hôm nay.</summary>
    private async Task CheckDailyLimitsAsync(
        Dictionary<int, Food> foods, List<PricedLine> lines, List<LineErrorDto> errors, CancellationToken ct)
    {
        var limited = lines.Where(l => foods[l.FoodId].DailyLimit is not null).ToList();
        if (limited.Count == 0) return;

        var sold = await SalesQueries.SoldTodayAsync(db, limited.Select(l => l.FoodId).Distinct().ToList(), clock, ct);

        foreach (var group in limited.GroupBy(l => l.FoodId))
        {
            var food = foods[group.Key];
            var remaining = Math.Max(0, food.DailyLimit!.Value - sold.GetValueOrDefault(food.Id));
            if (group.Sum(l => l.Quantity) <= remaining) continue;

            var message = remaining == 0
                ? $"{food.Name} đã hết suất hôm nay."
                : $"{food.Name} chỉ còn {remaining} suất hôm nay.";
            foreach (var line in group)
                errors.Add(new LineErrorDto(line.Index, food.Id, ErrorCodes.ItemSoldOut, message, remaining));
        }
    }
}
