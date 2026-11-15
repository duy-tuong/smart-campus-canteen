using System.Globalization;
using CanteenApi.Common;
using CanteenApi.Options;
using Microsoft.Extensions.Options;
using PayOS;
using PayOS.Exceptions;
using PayOS.Models.V2.PaymentRequests;

namespace CanteenApi.Services.Payments;

/// <summary>Lỗi khi gọi cổng thanh toán (mạng, sai khóa, payOS từ chối) → 502 PAYMENT_PROVIDER_ERROR.</summary>
public sealed class PaymentProviderException(string message, Exception? inner = null)
    : AppException(StatusCodes.Status502BadGateway, ErrorCodes.PaymentProviderError, message)
{
    public Exception? Provider { get; } = inner;
}

/// <summary>
/// Cài đặt <see cref="IPaymentGateway"/> bằng SDK chính thức payOS (NuGet "payOS" 2.x).
/// SDK tự ký request (HMAC-SHA256 bằng checksum key) và tự xác thực chữ ký response/webhook.
/// </summary>
public sealed class PayOsGateway : IPaymentGateway, IDisposable
{
    private readonly PayOsOptions _options;
    private readonly ILogger<PayOsGateway> _logger;
    private readonly Lazy<PayOSClient> _client;

    public PayOsGateway(IOptions<PayOsOptions> options, ILogger<PayOsGateway> logger)
    {
        _options = options.Value;
        _logger = logger;
        _client = new Lazy<PayOSClient>(() => new PayOSClient(new PayOSOptions
        {
            ClientId = _options.ClientId,
            ApiKey = _options.ApiKey,
            ChecksumKey = _options.ChecksumKey,
            TimeoutMs = 20_000,
            MaxRetries = 2,
        }));
    }

    public bool IsEnabled => _options.IsConfigured;

    private PayOSClient Client => IsEnabled
        ? _client.Value
        : throw new PaymentProviderException("Thanh toán chuyển khoản chưa được bật.");

    public async Task<PaymentLinkResult> CreateLinkAsync(CreatePaymentLinkInput input, CancellationToken ct)
    {
        var response = await CallAsync("tạo link thanh toán", () => Client.PaymentRequests.CreateAsync(new CreatePaymentLinkRequest
        {
            OrderCode = input.OrderCode,
            Amount = input.Amount,
            Description = input.Description,
            ReturnUrl = input.ReturnUrl,
            CancelUrl = input.CancelUrl,
            ExpiredAt = new DateTimeOffset(input.ExpiresAtUtc, TimeSpan.Zero).ToUnixTimeSeconds(),
            BuyerName = input.BuyerName,
        }));

        return new PaymentLinkResult(
            response.PaymentLinkId, response.CheckoutUrl, response.QrCode, response.Description,
            response.Bin, response.AccountNumber, response.AccountName);
    }

    public async Task<GatewayPaymentStatus> GetStatusAsync(long orderCode, CancellationToken ct)
    {
        var link = await CallAsync("kiểm tra thanh toán", () => Client.PaymentRequests.GetAsync(orderCode));
        var last = link.Transactions?.LastOrDefault();
        return new GatewayPaymentStatus(
            Map(link.Status), link.Amount, link.AmountPaid, last?.Reference, ParseVietnamTime(last?.TransactionDateTime));
    }

    public Task CancelLinkAsync(long orderCode, string reason, CancellationToken ct) =>
        CallAsync("hủy link thanh toán", () => Client.PaymentRequests.CancelAsync(orderCode, reason));

    public async Task<VerifiedPaymentWebhook> VerifyWebhookAsync(string rawBody)
    {
        try
        {
            var data = await Client.Webhooks.VerifyAsync(rawBody);
            return new VerifiedPaymentWebhook(
                data.OrderCode, data.Amount, data.Reference, ParseVietnamTime(data.TransactionDateTime), data.Code);
        }
        catch (Exception ex) when (ex is InvalidSignatureException or WebhookException or System.Text.Json.JsonException)
        {
            throw new InvalidWebhookException(ex.Message);
        }
    }

    public async Task<string> ConfirmWebhookUrlAsync(string url, CancellationToken ct)
    {
        var result = await CallAsync("đăng ký webhook", () => Client.Webhooks.ConfirmAsync(url));
        return $"{result.AccountName} - {result.AccountNumber}";
    }

    public void Dispose()
    {
        if (_client.IsValueCreated) _client.Value.Dispose();
    }

    /// <summary>Gọi payOS; mọi lỗi SDK/mạng được ghi log và chuyển thành 502 với thông báo dễ hiểu.</summary>
    private async Task<T> CallAsync<T>(string action, Func<Task<T>> call)
    {
        try
        {
            return await call();
        }
        catch (PayOSException ex)
        {
            var detail = ex is ApiException api ? $" ({api.ErrorCode}: {api.ErrorDescription})" : "";
            _logger.LogError(ex, "payOS lỗi khi {Action}{Detail}", action, detail);
            throw new PaymentProviderException($"Cổng thanh toán payOS lỗi khi {action}. Vui lòng thử lại sau.", ex);
        }
        catch (HttpRequestException ex)
        {
            _logger.LogError(ex, "Không kết nối được payOS khi {Action}", action);
            throw new PaymentProviderException("Không kết nối được cổng thanh toán. Vui lòng thử lại sau.", ex);
        }
    }

    private static GatewayLinkStatus Map(PaymentLinkStatus status) => status switch
    {
        PaymentLinkStatus.Paid => GatewayLinkStatus.Paid,
        PaymentLinkStatus.Underpaid => GatewayLinkStatus.Underpaid,
        PaymentLinkStatus.Processing => GatewayLinkStatus.Processing,
        PaymentLinkStatus.Cancelled => GatewayLinkStatus.Cancelled,
        PaymentLinkStatus.Expired => GatewayLinkStatus.Expired,
        PaymentLinkStatus.Failed => GatewayLinkStatus.Failed,
        _ => GatewayLinkStatus.Pending,
    };

    /// <summary>payOS trả thời gian giao dịch theo giờ Việt Nam, dạng "yyyy-MM-dd HH:mm:ss" (có thể kèm offset).</summary>
    private static DateTime? ParseVietnamTime(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        if (DateTimeOffset.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.None, out var withOffset)
            && value.Contains('+'))
            return withOffset.UtcDateTime;
        if (DateTime.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.None, out var local))
            return TimeZoneInfo.ConvertTimeToUtc(DateTime.SpecifyKind(local, DateTimeKind.Unspecified), VietnamTime.Zone);
        return null;
    }
}
