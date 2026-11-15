using System.Collections.Concurrent;
using System.Text.Json;
using CanteenApi.Services.Payments;

namespace CanteenApi.Tests.Infrastructure;

/// <summary>
/// Cổng thanh toán giả cho test: không gọi payOS thật, ghi lại các lời gọi và cho phép dựng kịch bản
/// (link lỗi, khách đã trả tiền...). Webhook giả hợp lệ khi "signature" = <see cref="ValidSignature"/>.
/// </summary>
public sealed class FakePaymentGateway : IPaymentGateway
{
    public const string ValidSignature = "chu-ky-hop-le";

    public bool Enabled { get; set; } = true;
    public bool FailNextCreate { get; set; }

    public ConcurrentQueue<CreatePaymentLinkInput> CreatedLinks { get; } = new();
    public ConcurrentQueue<long> CancelledLinks { get; } = new();

    /// <summary>Trạng thái link theo orderCode (mặc định Pending).</summary>
    public ConcurrentDictionary<long, GatewayPaymentStatus> Statuses { get; } = new();

    public void Reset()
    {
        Enabled = true;
        FailNextCreate = false;
        CreatedLinks.Clear();
        CancelledLinks.Clear();
        Statuses.Clear();
    }

    /// <summary>Giả lập khách đã chuyển khoản đủ tiền.</summary>
    public void SimulatePaid(long orderCode, long amount, string reference = "FT-TEST-001") =>
        Statuses[orderCode] = new GatewayPaymentStatus(GatewayLinkStatus.Paid, amount, amount, reference,
            CanteenApiFactory.Now.UtcDateTime);

    public bool IsEnabled => Enabled;

    public Task<PaymentLinkResult> CreateLinkAsync(CreatePaymentLinkInput input, CancellationToken ct)
    {
        if (FailNextCreate)
        {
            FailNextCreate = false;
            throw new PaymentProviderException("payOS giả lập lỗi.");
        }
        CreatedLinks.Enqueue(input);
        return Task.FromResult(new PaymentLinkResult(
            $"link-{input.OrderCode}", $"https://pay.payos.vn/web/link-{input.OrderCode}",
            $"00020101021238570010A000000727{input.OrderCode}", input.Description,
            "970422", "0123456789", "CANTEEN DEMO"));
    }

    public Task<GatewayPaymentStatus> GetStatusAsync(long orderCode, CancellationToken ct) =>
        Task.FromResult(Statuses.GetValueOrDefault(orderCode,
            new GatewayPaymentStatus(GatewayLinkStatus.Pending, 0, 0, null, null)));

    public Task CancelLinkAsync(long orderCode, string reason, CancellationToken ct)
    {
        CancelledLinks.Enqueue(orderCode);
        return Task.CompletedTask;
    }

    public Task<VerifiedPaymentWebhook> VerifyWebhookAsync(string rawBody)
    {
        var json = JsonDocument.Parse(rawBody).RootElement;
        if (json.GetProperty("signature").GetString() != ValidSignature)
            throw new InvalidWebhookException("Sai chữ ký (giả lập).");

        var data = json.GetProperty("data");
        return Task.FromResult(new VerifiedPaymentWebhook(
            data.GetProperty("orderCode").GetInt64(), data.GetProperty("amount").GetInt64(),
            data.GetProperty("reference").GetString()!, CanteenApiFactory.Now.UtcDateTime,
            data.GetProperty("code").GetString()!));
    }

    public Task<string> ConfirmWebhookUrlAsync(string url, CancellationToken ct) =>
        Task.FromResult("CANTEEN DEMO - 0123456789");
}
