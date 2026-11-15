using System.Diagnostics;
using Microsoft.AspNetCore.Mvc;

namespace CanteenApi.Common;

/// <summary>
/// Tạo response lỗi theo chuẩn RFC 7807 (application/problem+json) với định dạng thống nhất:
/// { type, title, status, detail, code, traceId, errors? }
/// </summary>
public static class Problems
{
    private static readonly Dictionary<int, string> Titles = new()
    {
        [400] = "Yêu cầu không hợp lệ",
        [401] = "Chưa đăng nhập",
        [403] = "Không có quyền truy cập",
        [404] = "Không tìm thấy",
        [409] = "Xung đột dữ liệu",
        [422] = "Vi phạm quy tắc nghiệp vụ",
        [500] = "Lỗi máy chủ",
    };

    public static ProblemDetails Create(HttpContext http, int status, string code, string? detail)
    {
        var problem = new ProblemDetails
        {
            Status = status,
            Title = Titles.GetValueOrDefault(status, "Lỗi"),
            Detail = detail,
            Type = $"https://httpstatuses.io/{status}",
            Instance = http.Request.Path,
        };
        problem.Extensions["code"] = code;
        AddTraceId(http, problem);
        return problem;
    }

    /// <summary>Gắn traceId để tra log khi người dùng báo lỗi.</summary>
    public static void AddTraceId(HttpContext http, ProblemDetails problem) =>
        problem.Extensions["traceId"] = Activity.Current?.Id ?? http.TraceIdentifier;

    /// <summary>Ghi ProblemDetails ra response (dùng ở middleware/handler, nơi không có IActionResult).</summary>
    public static Task WriteAsync(
        HttpContext http, int status, string code, string? detail,
        IReadOnlyDictionary<string, object?>? extensions = null)
    {
        var problem = Create(http, status, code, detail);
        foreach (var (key, value) in extensions ?? new Dictionary<string, object?>())
            problem.Extensions[key] = value;

        http.Response.StatusCode = status;
        // Dùng JsonOptions của MVC để trường mở rộng cũng theo camelCase + enum dạng chuỗi như mọi response khác.
        var json = http.RequestServices.GetService<Microsoft.Extensions.Options.IOptions<Microsoft.AspNetCore.Mvc.JsonOptions>>();
        return http.Response.WriteAsJsonAsync(
            problem,
            options: json?.Value.JsonSerializerOptions,
            contentType: "application/problem+json");
    }
}
