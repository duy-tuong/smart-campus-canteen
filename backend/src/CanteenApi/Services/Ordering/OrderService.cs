using System.Data;
using CanteenApi.Auth;
using CanteenApi.Common;
using CanteenApi.Data;
using CanteenApi.Dtos.Orders;
using CanteenApi.Models;
using CanteenApi.Options;
using CanteenApi.Services.Notifications;
using CanteenApi.Services.Payments;
using CanteenApi.Services.Realtime;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace CanteenApi.Services.Ordering;

/// <summary>Nghiệp vụ đặt món và truy vấn đơn hàng.</summary>
public sealed class OrderService(
    CanteenDbContext db,
    OrderPricingService pricing,
    VoucherService vouchers,
    IPaymentGateway gateway,
    PaymentService payments,
    NotificationService notifications,
    IRealtimePublisher realtime,
    IPublicUrlBuilder urls,
    IOptions<CanteenOptions> canteenOptions,
    TimeProvider clock,
    ILogger<OrderService> logger)
{
    private static readonly OrderStatus[] ActiveStatuses = [OrderStatus.Received, OrderStatus.Cooking, OrderStatus.Ready];

    /// <summary>Thời gian chờ thêm cho mỗi đơn đang xếp hàng trước (ước lượng giờ xong món).</summary>
    private const int MinutesPerQueuedOrder = 2;

    private CanteenOptions Canteen => canteenOptions.Value;

    // ============================ Đặt món ============================

    /// <summary>
    /// Tạo đơn. Toàn bộ chạy trong MỘT transaction có khóa ứng dụng (sp_getapplock "order-create"):
    /// các đơn được tạo tuần tự nên
    ///  - không bán quá số suất trong ngày khi nhiều người cùng đặt suất cuối,
    ///  - mã nhận món tăng dần, không trùng trong ngày.
    /// Ở quy mô căn-tin, thời gian chờ khóa (vài mili giây) không đáng kể; cách này đơn giản và đúng hơn khóa từng dòng.
    /// </summary>
    /// <returns>Đơn vừa tạo, hoặc đơn đã có nếu Idempotency-Key đã được dùng (Created = false).</returns>
    public async Task<(OrderDetailDto Order, bool Created)> CreateAsync(
        string uid, string? idempotencyKey, CreateOrderRequest request, CancellationToken ct)
    {
        var key = ValidateIdempotencyKey(idempotencyKey);
        if (await FindByRequestIdAsync(uid, key, ct) is { } existingId)
            return (await GetDetailAsync(existingId, uid, isStaff: false, ct), false);

        var method = request.PaymentMethod!.Value;
        if (method == PaymentMethod.BankTransfer && !gateway.IsEnabled)
            throw new BusinessRuleException(ErrorCodes.PaymentMethodUnavailable,
                "Căn-tin chưa bật thanh toán chuyển khoản. Vui lòng chọn thanh toán tiền mặt.");

        var nowUtc = clock.GetUtcNow().UtcDateTime;
        var nowVn = VietnamTime.Now(clock);
        EnsureOpen(nowVn);

        Order created;
        try
        {
            await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.ReadCommitted, ct);
            await AcquireOrderLockAsync(ct);

            // Kiểm tra lại trong khóa: request trùng gửi song song chỉ tạo một đơn.
            if (await FindByRequestIdAsync(uid, key, ct) is { } raced)
                return (await GetDetailAsync(raced, uid, isStaff: false, ct), false);

            var activeCount = await db.Orders.CountAsync(o => o.UserId == uid && ActiveStatuses.Contains(o.Status), ct);
            if (activeCount >= Canteen.MaxActiveOrdersPerUser)
                throw new BusinessRuleException(ErrorCodes.TooManyActiveOrders,
                    $"Bạn đang có {activeCount} đơn chưa hoàn thành (tối đa {Canteen.MaxActiveOrdersPerUser}). " +
                    "Vui lòng nhận món hoặc hủy bớt đơn trước khi đặt thêm.");

            var priced = await pricing.PriceAsync(request.Items, request.VoucherCode, uid, ct);
            if (!priced.CanOrder)
                throw new BusinessRuleException(ErrorCodes.OrderItemsInvalid,
                        "Một số món trong giỏ không thể đặt. Vui lòng kiểm tra lại giỏ hàng.")
                    .With("items", priced.Errors);

            // Đặt hàng mà gửi mã giảm giá sai → báo lỗi (không âm thầm tính đủ tiền).
            if (priced.Voucher is { IsValid: false } badVoucher)
                throw new BusinessRuleException(badVoucher.Check.ErrorCode!, badVoucher.Check.Message);

            var maxPrep = priced.Lines.Max(l => l.PrepTimeMinutes);
            var pickupUtc = ValidatePickupTime(request.PickupTime, nowUtc, nowVn, maxPrep);

            if (priced.Voucher?.VoucherId is { } voucherId && !await vouchers.TryConsumeAsync(voucherId, ct))
                throw new BusinessRuleException(ErrorCodes.VoucherExhausted, "Mã giảm giá vừa hết lượt sử dụng.");

            var today = DateOnly.FromDateTime(nowVn);
            var pickupCode = await NextPickupCodeAsync(today, ct);
            var queue = await db.Orders.CountAsync(o =>
                o.PickupDate == today && (o.Status == OrderStatus.Received || o.Status == OrderStatus.Cooking), ct);
            var estimated = nowUtc.AddMinutes(maxPrep + MinutesPerQueuedOrder * queue);

            var order = new Order
            {
                Id = Guid.NewGuid().ToString(),
                PickupDate = today,
                PickupCode = pickupCode,
                ClientRequestId = key,
                UserId = uid,
                Status = OrderStatus.Received,
                PaymentMethod = method,
                PaymentStatus = PaymentStatus.Pending,
                Subtotal = priced.Subtotal,
                DiscountAmount = priced.DiscountAmount,
                TotalAmount = priced.TotalAmount,
                VoucherId = priced.Voucher?.VoucherId,
                VoucherCode = priced.Voucher?.VoucherId is null ? null : priced.Voucher.Check.Code,
                PickupTime = pickupUtc,
                EstimatedReadyAt = pickupUtc is { } p && p > estimated ? p : estimated,
                Note = string.IsNullOrWhiteSpace(request.Note) ? null : request.Note.Trim(),
                Items = priced.Lines.Select(l => new OrderItem
                {
                    FoodId = l.FoodId,
                    FoodName = l.FoodName,
                    UnitPrice = l.UnitPrice,
                    OptionsPrice = l.OptionsPrice,
                    Quantity = l.Quantity,
                    LineTotal = l.LineTotal,
                    Note = l.Note,
                    Options = l.Options.Select(o => new OrderItemOption
                    {
                        GroupName = o.GroupName, OptionName = o.OptionName, ExtraPrice = o.ExtraPrice,
                    }).ToList(),
                }).ToList(),
                StatusHistory =
                {
                    new OrderStatusHistory
                    {
                        FromStatus = null, ToStatus = OrderStatus.Received, ChangedByUserId = uid,
                        Note = "Đặt món", ChangedAt = nowUtc,
                    },
                },
                Payments =
                {
                    new Payment
                    {
                        Method = method, Amount = priced.TotalAmount, Status = PaymentStatus.Pending, CreatedAt = nowUtc,
                        // Giữ chỗ orderCode cho payOS ngay trong transaction (UNIQUE) — link được tạo sau khi commit.
                        ProviderOrderCode = method == PaymentMethod.BankTransfer
                            ? PaymentService.ProviderOrderCodeFor(nowVn, pickupCode)
                            : null,
                    },
                },
            };

            db.Orders.Add(order);
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            created = order;

            logger.LogInformation("Order {OrderId} #{Code} created by {Uid}: {Total}đ ({Method})",
                order.Id, order.PickupCode, uid, order.TotalAmount, method);
        }
        catch (DbUpdateException ex) when (ex.InnerException is SqlException { Number: 2601 or 2627 })
        {
            // Chốt chặn cuối: UNIQUE(UserId, ClientRequestId) — trả lại đơn đã tạo bởi request trùng.
            if (await FindByRequestIdAsync(uid, key, CancellationToken.None) is not { } dup) throw;
            return (await GetDetailAsync(dup, uid, isStaff: false, ct), false);
        }

        // Chuyển khoản: tạo link/QR payOS SAU khi commit (không giữ khóa trong lúc gọi mạng).
        // payOS lỗi → đơn tự hủy (hoàn suất, hoàn voucher) và trả 502 PAYMENT_PROVIDER_ERROR.
        if (method == PaymentMethod.BankTransfer)
            await payments.InitiateBankTransferAsync(created.Id, ct);

        var placed = notifications.ForOrder(created, OrderEvent.Placed);
        await db.SaveChangesAsync(ct);
        realtime.PublishOrder(created.Id);
        realtime.PublishNotification(placed.Id);

        return (await GetDetailAsync(created.Id, uid, isStaff: false, ct), true);
    }

    // ============================ Truy vấn ============================

    /// <summary>Chi tiết đơn. Chỉ chủ đơn hoặc staff/admin xem được; người khác nhận 404 (không lộ đơn có tồn tại).</summary>
    public async Task<OrderDetailDto> GetDetailAsync(string id, string viewerUid, bool isStaff, CancellationToken ct)
    {
        var order = await db.Orders.AsNoTracking().AsSplitQuery()
            .Include(o => o.User)
            .Include(o => o.Items).ThenInclude(i => i.Options)
            .Include(o => o.Items).ThenInclude(i => i.Food)
            .Include(o => o.StatusHistory).ThenInclude(h => h.ChangedByUser)
            .Include(o => o.Payments)
            .FirstOrDefaultAsync(o => o.Id == id, ct);

        if (order is null || (!isStaff && order.UserId != viewerUid))
            throw new NotFoundException("Không tìm thấy đơn hàng.");

        var payment = order.Payments
            .Where(p => p.Status != PaymentStatus.Refunded)
            .OrderBy(p => p.Id)
            .FirstOrDefault();

        return new OrderDetailDto(
            order.Id, order.PickupCode, order.PickupDate, order.Status, order.PaymentMethod, order.PaymentStatus,
            order.PaidAt, order.Subtotal, order.DiscountAmount, order.TotalAmount, order.Items.Sum(i => i.Quantity),
            order.VoucherCode, order.Note, order.CancelReason, order.PickupTime, order.EstimatedReadyAt,
            order.CreatedAt, order.UpdatedAt,
            new OrderCustomerDto(order.UserId, order.User!.FullName, order.User.StudentCode, order.User.Phone),
            order.Items.OrderBy(i => i.Id).Select(i => new OrderItemDto(
                i.Id, i.FoodId, i.FoodName, urls.Build(i.Food?.ImageUrl), i.UnitPrice, i.OptionsPrice, i.Quantity,
                i.LineTotal, i.Note,
                i.Options.OrderBy(o => o.Id).Select(o => new OrderItemOptionDto(o.GroupName, o.OptionName, o.ExtraPrice)).ToList()))
                .ToList(),
            order.StatusHistory.OrderBy(h => h.ChangedAt).ThenBy(h => h.Id).Select(h => new OrderStatusEventDto(
                h.FromStatus, h.ToStatus, h.ChangedByUser?.FullName ?? "Hệ thống", h.Note, h.ChangedAt)).ToList(),
            payment is null ? null : new PaymentInfoDto(
                payment.Method, payment.Status, payment.Amount, payment.PaidAt,
                payment.Status == PaymentStatus.Pending ? payment.CheckoutUrl : null,
                payment.Status == PaymentStatus.Pending ? payment.QrCode : null,
                payment.ExpiresAt, payment.TransferContent, payment.BankBin,
                payment.BankAccountNumber, payment.BankAccountName),
            CanCancel(order.Status, isStaff, order.UserId == viewerUid),
            isStaff ? OrderLifecycleService.NextStatuses(order.Status) : []);
    }

    /// <summary>Đơn của tôi, mới nhất trước.</summary>
    public Task<PagedResult<OrderSummaryDto>> ListMineAsync(string uid, MyOrdersQuery query, CancellationToken ct)
    {
        var orders = db.Orders.AsNoTracking().Where(o => o.UserId == uid);
        orders = query.Status switch
        {
            "active" => orders.Where(o => ActiveStatuses.Contains(o.Status)),
            "completed" => orders.Where(o => o.Status == OrderStatus.Completed),
            "cancelled" => orders.Where(o => o.Status == OrderStatus.Cancelled),
            _ => orders,
        };

        return ToSummaryPageAsync(orders.OrderByDescending(o => o.CreatedAt), query, ct);
    }

    /// <summary>Bảng đơn của căn-tin theo ngày: lọc trạng thái, tìm theo mã/tên/MSSV, sắp theo giờ cần giao.</summary>
    public Task<PagedResult<OrderSummaryDto>> ListForStaffAsync(StaffOrdersQuery query, CancellationToken ct)
    {
        var date = query.Date ?? DateOnly.FromDateTime(VietnamTime.Now(clock));
        var orders = db.Orders.AsNoTracking().Where(o => o.PickupDate == date);

        if (query.Status is { Count: > 0 } statuses) orders = orders.Where(o => statuses.Contains(o.Status));
        if (query.PaymentStatus is { } paymentStatus) orders = orders.Where(o => o.PaymentStatus == paymentStatus);

        if (!string.IsNullOrWhiteSpace(query.Q))
        {
            var term = query.Q.Trim().TrimStart('#');
            orders = orders.Where(o =>
                o.PickupCode == term ||
                EF.Functions.Collate(o.User!.FullName, SearchCollation.AccentInsensitive).Contains(term) ||
                (o.User.StudentCode != null && o.User.StudentCode.Contains(term)));
        }

        // Đơn cần giao sớm nhất lên đầu (giờ hẹn, nếu không có thì giờ dự kiến xong).
        var sorted = orders
            .OrderBy(o => o.PickupTime ?? o.EstimatedReadyAt ?? o.CreatedAt)
            .ThenBy(o => o.CreatedAt);

        return ToSummaryPageAsync(sorted, query, ct);
    }

    // ============================ Hỗ trợ ============================

    /// <summary>Quy tắc hủy: sinh viên hủy đơn của mình khi còn "Đã nhận"; staff/admin hủy được khi "Đã nhận" hoặc "Đang nấu".</summary>
    public static bool CanCancel(OrderStatus status, bool isStaff, bool isOwner) =>
        isStaff ? status is OrderStatus.Received or OrderStatus.Cooking
                : isOwner && status == OrderStatus.Received;

    private async Task<PagedResult<OrderSummaryDto>> ToSummaryPageAsync(
        IQueryable<Order> orders, PageQuery query, CancellationToken ct)
    {
        var page = await orders
            .Select(o => new
            {
                o.Id, o.PickupCode, o.Status, o.PaymentMethod, o.PaymentStatus, o.TotalAmount,
                o.PickupTime, o.EstimatedReadyAt, o.CreatedAt,
                CustomerName = o.User!.FullName,
                o.User.StudentCode,
                Items = o.Items.OrderBy(i => i.Id).Select(i => new { i.FoodName, i.Quantity }).ToList(),
            })
            .ToPagedResultAsync(query, ct);

        return new PagedResult<OrderSummaryDto>(
            page.Items.Select(o => new OrderSummaryDto(
                o.Id, o.PickupCode, o.Status, o.PaymentMethod, o.PaymentStatus, o.TotalAmount,
                o.Items.Sum(i => i.Quantity),
                string.Join(", ", o.Items.Select(i => $"{i.FoodName} ×{i.Quantity}")),
                o.CustomerName, o.StudentCode, o.PickupTime, o.EstimatedReadyAt, o.CreatedAt)).ToList(),
            page.Page, page.PageSize, page.TotalCount);
    }

    private static string ValidateIdempotencyKey(string? key)
    {
        if (string.IsNullOrWhiteSpace(key) || !Guid.TryParse(key, out var guid))
            throw new BadRequestException(ErrorCodes.ValidationError,
                "Thiếu header Idempotency-Key (GUID do app sinh cho mỗi lần đặt món).");
        return guid.ToString("D");
    }

    private Task<string?> FindByRequestIdAsync(string uid, string key, CancellationToken ct) =>
        db.Orders.AsNoTracking()
            .Where(o => o.UserId == uid && o.ClientRequestId == key)
            .Select(o => o.Id)
            .FirstOrDefaultAsync(ct);

    private void EnsureOpen(DateTime nowVn)
    {
        var time = TimeOnly.FromDateTime(nowVn);
        if (time < Canteen.OpenTime || time >= Canteen.CloseTime)
            throw new BusinessRuleException(ErrorCodes.CanteenClosed,
                $"Căn-tin chỉ nhận đơn từ {Canteen.OpenTime:HH\\:mm} đến {Canteen.CloseTime:HH\\:mm}.");
    }

    /// <summary>
    /// Giờ hẹn lấy món: trong HÔM NAY (giờ VN), trong giờ mở cửa, và không sớm hơn
    /// bây giờ + max(thời gian chế biến lâu nhất, MinPickupLeadMinutes).
    /// </summary>
    private DateTime? ValidatePickupTime(DateTimeOffset? requested, DateTime nowUtc, DateTime nowVn, int maxPrepMinutes)
    {
        if (requested is null) return null;

        var pickupUtc = requested.Value.UtcDateTime;
        var pickupVn = TimeZoneInfo.ConvertTimeFromUtc(pickupUtc, VietnamTime.Zone);
        var earliest = nowUtc.AddMinutes(Math.Max(maxPrepMinutes, Canteen.MinPickupLeadMinutes));

        string? error = null;
        if (pickupVn.Date != nowVn.Date)
            error = "Chỉ đặt hẹn lấy món trong ngày hôm nay.";
        else if (TimeOnly.FromDateTime(pickupVn) is var t && (t < Canteen.OpenTime || t > Canteen.CloseTime))
            error = $"Giờ hẹn phải trong giờ mở cửa ({Canteen.OpenTime:HH\\:mm}–{Canteen.CloseTime:HH\\:mm}).";
        else if (pickupUtc < earliest)
            error = $"Giờ hẹn sớm nhất là {TimeZoneInfo.ConvertTimeFromUtc(earliest, VietnamTime.Zone):HH\\:mm} (cần thời gian chuẩn bị món).";

        if (error is not null) throw new BusinessRuleException(ErrorCodes.PickupTimeInvalid, error);
        return pickupUtc;
    }

    /// <summary>Khóa ứng dụng của SQL Server, tự nhả khi transaction kết thúc (commit/rollback).</summary>
    private Task AcquireOrderLockAsync(CancellationToken ct) =>
        db.Database.ExecuteSqlRawAsync("""
            DECLARE @result int;
            EXEC @result = sp_getapplock @Resource = N'order-create', @LockMode = N'Exclusive',
                                         @LockOwner = N'Transaction', @LockTimeout = 15000;
            IF @result < 0 THROW 51000, N'Hệ thống đang bận, vui lòng thử lại.', 1;
            """, ct);

    /// <summary>Mã nhận món tiếp theo trong ngày: "001", "002"... (chạy trong khóa nên không trùng).</summary>
    private async Task<string> NextPickupCodeAsync(DateOnly day, CancellationToken ct)
    {
        var codes = await db.Orders.Where(o => o.PickupDate == day).Select(o => o.PickupCode).ToListAsync(ct);
        var max = codes.Select(c => int.TryParse(c, out var n) ? n : 0).DefaultIfEmpty(0).Max();
        return (max + 1).ToString("000");
    }
}
