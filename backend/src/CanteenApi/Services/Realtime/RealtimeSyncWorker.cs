namespace CanteenApi.Services.Realtime;

/// <summary>
/// Chạy nền: lấy việc từ <see cref="RealtimeQueue"/> và ghi lên Firebase.
///  - Lỗi (mất mạng, Firebase chậm) → thử lại tối đa 5 lần, chờ 1s, 2s, 4s, 8s, 16s.
///  - Khi khởi động: đồng bộ lại toàn bộ đơn đang xử lý.
///  - Mỗi giờ: dọn đơn đã xong/hủy quá 24 giờ khỏi Firebase.
/// </summary>
public sealed class RealtimeSyncWorker(
    RealtimeQueue queue,
    IServiceScopeFactory scopes,
    ILogger<RealtimeSyncWorker> logger) : BackgroundService
{
    private const int MaxAttempts = 5;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await RunInScopeAsync("đồng bộ lại đơn đang xử lý", async s =>
            logger.LogInformation("Realtime: đã đồng bộ lại {Count} đơn đang xử lý", await s.ResyncActiveOrdersAsync(stoppingToken)));

        _ = CleanupLoopAsync(stoppingToken);

        await foreach (var job in queue.Reader.ReadAllAsync(stoppingToken))
        {
            try
            {
                await using var scope = scopes.CreateAsyncScope();
                await scope.ServiceProvider.GetRequiredService<RealtimeSyncService>().ProcessAsync(job, stoppingToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                if (job.Attempt + 1 >= MaxAttempts)
                {
                    logger.LogError(ex, "Realtime: bỏ qua {Kind} {Key} sau {Attempts} lần thử", job.Kind, job.Key, MaxAttempts);
                    continue;
                }

                var delay = TimeSpan.FromSeconds(Math.Pow(2, job.Attempt));
                logger.LogWarning("Realtime: lỗi {Kind} {Key} ({Message}) — thử lại sau {Delay}s",
                    job.Kind, job.Key, ex.Message, delay.TotalSeconds);
                _ = RequeueLaterAsync(job with { Attempt = job.Attempt + 1 }, delay, stoppingToken);
            }
        }
    }

    private async Task RequeueLaterAsync(RealtimeJob job, TimeSpan delay, CancellationToken ct)
    {
        try
        {
            await Task.Delay(delay, ct);
            queue.Enqueue(job);
        }
        catch (OperationCanceledException) { }
    }

    private async Task CleanupLoopAsync(CancellationToken ct)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromHours(1));
        while (await timer.WaitForNextTickAsync(ct).ConfigureAwait(false))
        {
            await RunInScopeAsync("dọn đơn cũ", async s =>
                logger.LogInformation("Realtime: đã dọn {Count} đơn cũ", await s.CleanupFinishedOrdersAsync(ct)));
        }
    }

    private async Task RunInScopeAsync(string action, Func<RealtimeSyncService, Task> work)
    {
        try
        {
            await using var scope = scopes.CreateAsyncScope();
            await work(scope.ServiceProvider.GetRequiredService<RealtimeSyncService>());
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Realtime: lỗi khi {Action}", action);
        }
    }
}
