using CanteenApi.Common;
using CanteenApi.Data;
using CanteenApi.Models;
using CanteenApi.Options;
using CanteenApi.Services.Ordering;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace CanteenApi.Services.Payments;

/// <summary>Kết quả ghi nhận một khoản thanh toán.</summary>
public enum MarkPaidResult
{
    Paid,
    AlreadyPaid,
    AmountMismatch,
    NotFound,
    /// <summary>Tiền về sau khi đơn đã hủy → ghi nhận cần hoàn tiền.</summary>
    PaidAfterCancel,
}

/// <summary>
/// Thanh toán chuyển khoản qua payOS:
///  - tạo link/QR cho đơn mới;
///  - xác nhận đã thanh toán qua 3 đường (webhook, đồng bộ chủ động, staff xác nhận tay)
///    — tất cả đi qua <see cref="MarkPaidAsync"/> nên an toàn khi cùng một giao dịch được báo nhiều lần.
/// </summary>
public sealed class PaymentService(
    CanteenDbContext db,
    IPaymentGateway gateway,
    OrderLifecycleService lifecycle,
    IPublicUrlBuilder urls,
    IOptions<CanteenOptions> canteenOptions,
    TimeProvider clock,
    ILogger<PaymentService> logger)
{
    /// <summary>orderCode gửi payOS: yyMMdd × 10000 + số thứ tự trong ngày (duy nhất, ví dụ 2611160015).</summary>
    public static long ProviderOrderCodeFor(DateOnly day, string pickupCode) =>
        long.Parse(day.ToString("yyMMdd")) * 10_000 + int.Parse(pickupCode);

    /// <summary>Nội dung chuyển khoản ≤ 9 ký tự (giới hạn của payOS với tài khoản không liên kết): "SC" + 7 số cuối.</summary>
    public static string TransferContentFor(long orderCode) => $"SC{orderCode % 10_000_000:D7}";

    // ============================ Tạo link thanh toán ============================

    /// <summary>
    /// Tạo link payOS cho đơn chuyển khoản vừa tạo (gọi SAU khi commit đơn, không giữ khóa trong lúc gọi mạng).
    /// payOS lỗi → hủy đơn (hoàn suất, hoàn voucher) rồi báo 502 để app cho người dùng đặt lại.
    /// </summary>
    public async Task InitiateBankTransferAsync(string orderId, CancellationToken ct)
    {
        var order = await db.Orders.Include(o => o.Payments).Include(o => o.User)
            .FirstAsync(o => o.Id == orderId, ct);
        var payment = order.Payments.Single(p => p.Status == PaymentStatus.Pending && p.ProviderOrderCode != null);
        var orderCode = payment.ProviderOrderCode!.Value;
        var expiresAt = clock.GetUtcNow().UtcDateTime.AddMinutes(canteenOptions.Value.UnpaidTransferTimeoutMinutes);
        var resultUrl = PublicUrl($"/payment/result?orderId={orderId}");

        try
        {
            var link = await gateway.CreateLinkAsync(new CreatePaymentLinkInput(
                orderCode, order.TotalAmount, TransferContentFor(orderCode), resultUrl, resultUrl, expiresAt,
                order.User?.FullName), ct);

            payment.PaymentLinkId = link.PaymentLinkId;
            payment.CheckoutUrl = link.CheckoutUrl;
            payment.QrCode = link.QrCode;
            payment.ExpiresAt = expiresAt;
            payment.TransferContent = link.Description;
            payment.BankBin = link.BankBin;
            payment.BankAccountNumber = link.AccountNumber;
            payment.BankAccountName = link.AccountName;
            await db.SaveChangesAsync(ct);
        }
        catch (PaymentProviderException)
        {
            await lifecycle.CancelAsync(order, "Không tạo được thanh toán chuyển khoản", actorUid: null, CancellationToken.None);
            throw;
        }
    }

    // ============================ Xác nhận đã thanh toán ============================

    /// <summary>
    /// Ghi nhận đã nhận tiền cho orderCode. Idempotent:
    ///  - đã Paid → bỏ qua (webhook gửi lại, poller và webhook cùng lúc...)
    ///  - thiếu tiền → không chuyển Paid (log để staff xử lý)
    ///  - hai luồng chạy đồng thời → RowVersion của đơn bảo đảm chỉ một luồng ghi thành công
    /// </summary>
    public async Task<MarkPaidResult> MarkPaidAsync(
        long orderCode, long amount, string reference, DateTime? paidAtUtc, string source, CancellationToken ct)
    {
        var payment = await db.Payments.Include(p => p.Order).ThenInclude(o => o!.Payments)
            .FirstOrDefaultAsync(p => p.ProviderOrderCode == orderCode, ct);
        if (payment?.Order is not { } order)
        {
            logger.LogWarning("[{Source}] Nhận thanh toán cho orderCode {OrderCode} không tồn tại", source, orderCode);
            return MarkPaidResult.NotFound;
        }

        return await ApplyPaymentAsync(order, payment, amount, reference, paidAtUtc, source, ct);
    }

    /// <summary>Staff xác nhận đã nhận tiền (khách đưa ảnh chụp chuyển khoản / trả tiền mặt trước).</summary>
    public async Task<MarkPaidResult> ConfirmManuallyAsync(string orderId, string staffUid, CancellationToken ct)
    {
        var order = await lifecycle.LoadForUpdateAsync(orderId, ct) ?? throw new NotFoundException("Không tìm thấy đơn hàng.");
        if (order.Status == OrderStatus.Cancelled)
            throw new BusinessRuleException(ErrorCodes.PaymentNotPending, "Đơn đã hủy, không thể xác nhận thanh toán.");
        if (order.PaymentStatus != PaymentStatus.Pending)
            throw new BusinessRuleException(ErrorCodes.PaymentNotPending, "Đơn đã được thanh toán trước đó.");

        var payment = order.Payments.Single(p => p.Status == PaymentStatus.Pending);
        var now = clock.GetUtcNow().UtcDateTime;
        var reference = $"MANUAL-{now:yyyyMMddHHmmss}-{order.PickupDate:yyMMdd}{order.PickupCode}";
        var result = await ApplyPaymentAsync(order, payment, order.TotalAmount, reference, now, $"staff:{staffUid}", ct);

        // Đã thu tay → hủy link payOS để khách không trả thêm lần nữa.
        if (result == MarkPaidResult.Paid && payment.ProviderOrderCode is { } code && gateway.IsEnabled)
        {
            try { await gateway.CancelLinkAsync(code, "Đã xác nhận thanh toán tại quầy", CancellationToken.None); }
            catch (Exception ex) { logger.LogWarning(ex, "Không hủy được link payOS {OrderCode}", code); }
        }
        return result;
    }

    /// <summary>
    /// Đồng bộ chủ động: hỏi payOS trạng thái link (dùng khi không nhận được webhook — ví dụ chạy local
    /// không có URL public, hoặc người dùng bấm "Tôi đã chuyển khoản").
    /// </summary>
    public async Task<MarkPaidResult?> SyncAsync(long orderCode, string source, CancellationToken ct)
    {
        if (!gateway.IsEnabled) return null;

        var status = await gateway.GetStatusAsync(orderCode, ct);
        if (status.Status != GatewayLinkStatus.Paid && status.AmountPaid < status.Amount) return null;

        return await MarkPaidAsync(orderCode, status.AmountPaid,
            status.Reference ?? $"PAYOS-{orderCode}", status.PaidAtUtc, source, ct);
    }

    /// <summary>Đồng bộ thanh toán của một đơn (chủ đơn hoặc staff gọi). Người khác → 404.</summary>
    public async Task SyncOrderAsync(string orderId, string viewerUid, bool isStaff, CancellationToken ct)
    {
        var info = await db.Orders.AsNoTracking()
            .Where(o => o.Id == orderId && (isStaff || o.UserId == viewerUid))
            .Select(o => new
            {
                o.PaymentStatus,
                Code = o.Payments.Where(p => p.ProviderOrderCode != null).Select(p => p.ProviderOrderCode).FirstOrDefault(),
            })
            .FirstOrDefaultAsync(ct)
            ?? throw new NotFoundException("Không tìm thấy đơn hàng.");

        if (info.PaymentStatus == PaymentStatus.Pending && info.Code is { } code)
            await SyncAsync(code, isStaff ? "sync:staff" : "sync:customer", ct);
    }

    // ============================ Hỗ trợ ============================

    private async Task<MarkPaidResult> ApplyPaymentAsync(
        Order order, Payment payment, long amount, string reference, DateTime? paidAtUtc, string source, CancellationToken ct)
    {
        if (order.PaymentStatus is PaymentStatus.Paid or PaymentStatus.Refunded || payment.Status == PaymentStatus.Paid)
            return MarkPaidResult.AlreadyPaid;

        if (amount < order.TotalAmount)
        {
            logger.LogWarning("[{Source}] Đơn {OrderId} nhận {Amount}đ < {Total}đ (ref {Ref}) — không chuyển Paid",
                source, order.Id, amount, order.TotalAmount, reference);
            return MarkPaidResult.AmountMismatch;
        }

        var paidAt = paidAtUtc ?? clock.GetUtcNow().UtcDateTime;
        payment.Status = PaymentStatus.Paid;
        payment.PaidAt = paidAt;
        payment.TransactionRef = reference;
        order.PaidAt = paidAt;

        var paidAfterCancel = order.Status == OrderStatus.Cancelled;
        if (paidAfterCancel)
        {
            // Tiền về sau khi đơn đã hủy: ghi nhận khoản phải hoàn cho khách.
            order.PaymentStatus = PaymentStatus.Refunded;
            order.Payments.Add(new Payment
            {
                Method = payment.Method, Amount = (int)amount, Status = PaymentStatus.Refunded,
                PaidAt = paidAt, CreatedAt = clock.GetUtcNow().UtcDateTime,
            });
        }
        else
        {
            order.PaymentStatus = PaymentStatus.Paid;
        }

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateConcurrencyException)
        {
            // Luồng khác (webhook/poller) vừa ghi nhận trước → kiểm tra lại.
            db.ChangeTracker.Clear();
            var current = await db.Orders.AsNoTracking().Where(o => o.Id == order.Id).Select(o => o.PaymentStatus).FirstAsync(ct);
            if (current is PaymentStatus.Paid or PaymentStatus.Refunded) return MarkPaidResult.AlreadyPaid;
            throw;
        }
        catch (DbUpdateException ex) when (ex.InnerException is SqlException { Number: 2601 or 2627 })
        {
            // Mã giao dịch ngân hàng đã được ghi nhận (UNIQUE TransactionRef).
            db.ChangeTracker.Clear();
            logger.LogWarning("[{Source}] Giao dịch {Ref} đã được ghi nhận trước đó", source, reference);
            return MarkPaidResult.AlreadyPaid;
        }

        if (paidAfterCancel)
        {
            logger.LogWarning("[{Source}] Đơn {OrderId} đã hủy nhưng nhận {Amount}đ (ref {Ref}) — CẦN HOÀN TIỀN",
                source, order.Id, amount, reference);
            return MarkPaidResult.PaidAfterCancel;
        }

        logger.LogInformation("[{Source}] Đơn {OrderId} đã thanh toán {Amount}đ (ref {Ref})", source, order.Id, amount, reference);
        // E4: thông báo "Đã xác nhận thanh toán" + đồng bộ realtime.
        return MarkPaidResult.Paid;
    }

    private string PublicUrl(string path)
    {
        var baseUrl = canteenOptions.Value.PublicBaseUrl;
        return string.IsNullOrWhiteSpace(baseUrl)
            ? urls.Build(path) ?? path
            : $"{baseUrl.TrimEnd('/')}{path}";
    }
}
