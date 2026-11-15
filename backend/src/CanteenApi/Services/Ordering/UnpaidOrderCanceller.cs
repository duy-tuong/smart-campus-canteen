using CanteenApi.Data;
using CanteenApi.Models;
using CanteenApi.Options;
using CanteenApi.Services.Payments;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace CanteenApi.Services.Ordering;

/// <summary>
/// Chạy nền mỗi phút: hủy các đơn chuyển khoản quá hạn thanh toán (mặc định 15 phút) để
/// trả suất và lượt voucher cho người khác. Trước khi hủy hỏi payOS một lần — không hủy nhầm
/// đơn khách vừa trả sát giờ.
/// </summary>
public sealed class UnpaidOrderCanceller(
    IServiceScopeFactory scopes,
    IOptions<CanteenOptions> options,
    TimeProvider clock,
    ILogger<UnpaidOrderCanceller> logger) : BackgroundService
{
    public const string ExpiredReason = "Quá hạn thanh toán";

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromMinutes(1));
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                var cancelled = await RunOnceAsync(stoppingToken);
                if (cancelled > 0) logger.LogInformation("Đã tự hủy {Count} đơn quá hạn thanh toán", cancelled);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogError(ex, "UnpaidOrderCanceller lỗi");
            }
        }
    }

    /// <summary>Một lượt (public để test gọi trực tiếp). Trả về số đơn đã hủy.</summary>
    public async Task<int> RunOnceAsync(CancellationToken ct)
    {
        var deadline = clock.GetUtcNow().UtcDateTime.AddMinutes(-options.Value.UnpaidTransferTimeoutMinutes);

        List<string> overdue;
        await using (var scope = scopes.CreateAsyncScope())
        {
            overdue = await scope.ServiceProvider.GetRequiredService<CanteenDbContext>().Orders.AsNoTracking()
                .Where(o => o.PaymentMethod == PaymentMethod.BankTransfer && o.Status == OrderStatus.Received &&
                            o.PaymentStatus == PaymentStatus.Pending && o.CreatedAt <= deadline)
                .OrderBy(o => o.CreatedAt)
                .Select(o => o.Id)
                .Take(50)
                .ToListAsync(ct);
        }

        var cancelled = 0;
        foreach (var orderId in overdue)
        {
            // Mỗi đơn một scope (DbContext) riêng: lỗi ở đơn này không ảnh hưởng đơn khác.
            await using var scope = scopes.CreateAsyncScope();
            var lifecycle = scope.ServiceProvider.GetRequiredService<OrderLifecycleService>();
            var payments = scope.ServiceProvider.GetRequiredService<PaymentService>();
            try
            {
                var order = await lifecycle.LoadForUpdateAsync(orderId, ct);
                if (order is null || order.Status != OrderStatus.Received || order.PaymentStatus != PaymentStatus.Pending)
                    continue;

                var code = order.Payments.FirstOrDefault(p => p.ProviderOrderCode != null)?.ProviderOrderCode;
                if (code is { } c && await payments.SyncAsync(c, "auto-cancel-check", ct) is MarkPaidResult.Paid or MarkPaidResult.AlreadyPaid)
                    continue; // khách vừa trả → không hủy

                // SyncAsync có thể đã đọc lại dữ liệu → tải lại đơn mới nhất trước khi hủy.
                scope.ServiceProvider.GetRequiredService<CanteenDbContext>().ChangeTracker.Clear();
                order = await lifecycle.LoadForUpdateAsync(orderId, ct);
                if (order is null || order.PaymentStatus != PaymentStatus.Pending) continue;

                await lifecycle.CancelAsync(order, ExpiredReason, actorUid: null, ct);
                cancelled++;
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogWarning(ex, "Không tự hủy được đơn {OrderId}", orderId);
            }
        }
        return cancelled;
    }
}
