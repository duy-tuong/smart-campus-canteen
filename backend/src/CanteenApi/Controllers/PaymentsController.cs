using System.ComponentModel.DataAnnotations;
using System.Net;
using CanteenApi.Auth;
using CanteenApi.Common;
using CanteenApi.Data;
using CanteenApi.Options;
using CanteenApi.Services.Payments;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace CanteenApi.Controllers;

/// <summary>Webhook của cổng thanh toán payOS (payOS gọi vào, không có token người dùng).</summary>
[ApiController]
[Route("api/payments")]
[Tags("Thanh toán")]
public class PaymentsController(IPaymentGateway gateway, PaymentService payments, ILogger<PaymentsController> logger)
    : ControllerBase
{
    /// <summary>
    /// payOS báo đã nhận tiền. Chữ ký được xác thực trên NỘI DUNG GỐC của request bằng checksum key.
    /// Chữ ký hợp lệ → luôn trả 200 (kể cả đã xử lý trước đó) để payOS không gửi lại; sai chữ ký → 400.
    /// </summary>
    [HttpPost("payos/webhook")]
    [AllowAnonymous]
    [Consumes("application/json")]
    public async Task<IActionResult> PayOsWebhook(CancellationToken ct)
    {
        if (!gateway.IsEnabled) return NotFound();

        using var reader = new StreamReader(Request.Body);
        var raw = await reader.ReadToEndAsync(ct);

        VerifiedPaymentWebhook data;
        try
        {
            data = await gateway.VerifyWebhookAsync(raw);
        }
        catch (InvalidWebhookException ex)
        {
            logger.LogWarning("Webhook payOS sai chữ ký: {Message}", ex.Message);
            throw new BadRequestException(ErrorCodes.InvalidWebhook, "Chữ ký webhook không hợp lệ.");
        }

        if (data.Code != "00")
        {
            logger.LogInformation("Webhook payOS orderCode {OrderCode} code {Code} — bỏ qua", data.OrderCode, data.Code);
            return Ok(new { success = true });
        }

        var result = await payments.MarkPaidAsync(data.OrderCode, data.Amount, data.Reference, data.PaidAtUtc, "webhook", ct);
        return Ok(new { success = true, result = result.ToString() });
    }
}

/// <summary>Đăng ký webhook với payOS (admin), dùng khi backend có URL public (tunnel cloudflared/ngrok hoặc deploy).</summary>
[ApiController]
[Route("api/admin/payos")]
[Authorize(Policy = Policies.AdminOnly)]
[Tags("Thanh toán")]
public class AdminPayOsController(IPaymentGateway gateway, IOptions<CanteenOptions> options) : ControllerBase
{
    public sealed record ConfirmWebhookRequest(
        [Url(ErrorMessage = "URL không hợp lệ.")] string? Url);

    /// <summary>
    /// Đăng ký URL webhook. Bỏ trống url → dùng {Canteen:PublicBaseUrl}/api/payments/payos/webhook.
    /// payOS sẽ gửi thử một giao dịch mẫu; URL chỉ được lưu nếu backend phản hồi 2xx.
    /// </summary>
    [HttpPost("confirm-webhook")]
    public async Task<IActionResult> ConfirmWebhook([FromBody] ConfirmWebhookRequest request, CancellationToken ct)
    {
        if (!gateway.IsEnabled)
            throw new BusinessRuleException(ErrorCodes.PaymentMethodUnavailable, "Chưa bật payOS.");

        var url = request.Url;
        if (string.IsNullOrWhiteSpace(url))
        {
            var baseUrl = options.Value.PublicBaseUrl;
            if (string.IsNullOrWhiteSpace(baseUrl))
                throw new BadRequestException(ErrorCodes.ValidationError,
                    "Chưa cấu hình Canteen:PublicBaseUrl — hãy truyền url hoặc cấu hình URL public.");
            url = $"{baseUrl.TrimEnd('/')}/api/payments/payos/webhook";
        }

        var account = await gateway.ConfirmWebhookUrlAsync(url, ct);
        return Ok(new { webhookUrl = url, account });
    }
}

/// <summary>
/// Trang trả về sau khi thanh toán trên trình duyệt (returnUrl / cancelUrl của payOS).
/// Kiểm tra ngay trạng thái với payOS rồi hiển thị thông báo quay lại ứng dụng.
/// </summary>
[ApiController]
[Route("payment/result")]
[AllowAnonymous]
[ApiExplorerSettings(IgnoreApi = true)]
public class PaymentResultController(CanteenDbContext db, PaymentService payments, ILogger<PaymentResultController> logger)
    : ControllerBase
{
    [HttpGet]
    public async Task<ContentResult> Get([FromQuery] string? orderId, [FromQuery] long? orderCode,
        [FromQuery] bool cancel, CancellationToken ct)
    {
        var code = orderCode ?? await db.Payments.AsNoTracking()
            .Where(p => p.OrderId == orderId && p.ProviderOrderCode != null)
            .Select(p => p.ProviderOrderCode).FirstOrDefaultAsync(ct);

        MarkPaidResult? result = null;
        if (code is { } c && !cancel)
        {
            try { result = await payments.SyncAsync(c, "return-url", ct); }
            catch (Exception ex) { logger.LogWarning(ex, "Không kiểm tra được thanh toán {OrderCode}", c); }
        }

        var (title, message) = cancel
            ? ("Đã hủy thanh toán", "Bạn đã hủy thanh toán. Đơn sẽ tự hủy nếu không thanh toán trong thời hạn.")
            : result is MarkPaidResult.Paid or MarkPaidResult.AlreadyPaid
                ? ("Thanh toán thành công", "Căn-tin đã nhận được tiền. Bạn có thể quay lại ứng dụng để theo dõi đơn.")
                : ("Đang xác nhận thanh toán", "Hệ thống sẽ tự cập nhật trong giây lát. Vui lòng quay lại ứng dụng.");

        return Content($"""
            <!doctype html><html lang="vi"><head><meta charset="utf-8">
            <meta name="viewport" content="width=device-width,initial-scale=1"><title>{WebUtility.HtmlEncode(title)}</title>
            <style>body{"{"}font-family:system-ui,sans-serif;display:grid;place-items:center;min-height:100vh;margin:0;padding:16px;background:#fff8f0;color:#222{"}"}
            main{"{"}max-width:420px;text-align:center{"}"}h1{"{"}color:#e65100{"}"}</style></head>
            <body><main><h1>{WebUtility.HtmlEncode(title)}</h1><p>{WebUtility.HtmlEncode(message)}</p></main></body></html>
            """, "text/html; charset=utf-8");
    }
}
