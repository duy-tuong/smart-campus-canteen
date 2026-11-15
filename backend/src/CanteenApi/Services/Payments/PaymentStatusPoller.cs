using CanteenApi.Data;
using CanteenApi.Models;
using CanteenApi.Options;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace CanteenApi.Services.Payments;

/// <summary>
/// Chạy nền: định kỳ hỏi payOS trạng thái các khoản chuyển khoản đang chờ.
/// Cần thiết khi backend chạy local (payOS không gọi được webhook vào localhost) và là lớp dự phòng
/// khi webhook bị mất. Nhờ MarkPaidAsync idempotent nên chạy song song với webhook vẫn an toàn.
/// </summary>
public sealed class PaymentStatusPoller(
    IServiceScopeFactory scopes,
    IOptions<WorkerOptions> options,
    TimeProvider clock,
    ILogger<PaymentStatusPoller> logger) : BackgroundService
{
    /// <summary>Số khoản kiểm tra tối đa mỗi lượt (tránh dồn quá nhiều request sang payOS).</summary>
    private const int BatchSize = 20;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var interval = TimeSpan.FromSeconds(options.Value.PaymentPollSeconds);
        logger.LogInformation("PaymentStatusPoller chạy mỗi {Seconds}s", interval.TotalSeconds);

        using var timer = new PeriodicTimer(interval);
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                await RunOnceAsync(stoppingToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogError(ex, "PaymentStatusPoller lỗi");
            }
        }
    }

    /// <summary>Một lượt kiểm tra (public để test gọi trực tiếp). Trả về số khoản đã được xác nhận thanh toán.</summary>
    public async Task<int> RunOnceAsync(CancellationToken ct)
    {
        await using var scope = scopes.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<CanteenDbContext>();
        var gateway = scope.ServiceProvider.GetRequiredService<IPaymentGateway>();
        var payments = scope.ServiceProvider.GetRequiredService<PaymentService>();
        if (!gateway.IsEnabled) return 0;

        // Còn hạn, hoặc vừa hết hạn trong 10 phút (khách có thể trả sát giờ).
        var since = clock.GetUtcNow().UtcDateTime.AddMinutes(-10);
        var codes = await db.Payments.AsNoTracking()
            .Where(p => p.Status == PaymentStatus.Pending && p.ProviderOrderCode != null &&
                        p.Order!.Status != OrderStatus.Cancelled && p.ExpiresAt > since)
            .OrderBy(p => p.CreatedAt)
            .Select(p => p.ProviderOrderCode!.Value)
            .Take(BatchSize)
            .ToListAsync(ct);

        var confirmed = 0;
        foreach (var code in codes)
        {
            try
            {
                if (await payments.SyncAsync(code, "poller", ct) == MarkPaidResult.Paid) confirmed++;
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogWarning(ex, "Không kiểm tra được thanh toán {OrderCode}", code);
            }
        }
        return confirmed;
    }
}
