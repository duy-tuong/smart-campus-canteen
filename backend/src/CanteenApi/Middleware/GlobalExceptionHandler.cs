using CanteenApi.Common;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace CanteenApi.Middleware;

/// <summary>
/// Bắt mọi exception chưa xử lý và chuyển thành ProblemDetails thống nhất.
/// Không bao giờ trả stack trace cho client; chi tiết lỗi chỉ ghi vào log (kèm traceId).
/// </summary>
public sealed class GlobalExceptionHandler(ILogger<GlobalExceptionHandler> logger) : IExceptionHandler
{
    // Mã lỗi SQL Server
    private const int SqlUniqueIndexViolation = 2601;
    private const int SqlUniqueConstraintViolation = 2627;
    private const int SqlConstraintViolation = 547; // CHECK / FOREIGN KEY

    public async ValueTask<bool> TryHandleAsync(HttpContext http, Exception exception, CancellationToken ct)
    {
        var (status, code, detail) = exception switch
        {
            AppException app => (app.StatusCode, app.Code, app.Message),

            DbUpdateConcurrencyException => (StatusCodes.Status409Conflict, ErrorCodes.ConcurrencyConflict,
                "Dữ liệu đã được người khác cập nhật. Vui lòng tải lại rồi thử lại."),

            DbUpdateException { InnerException: SqlException { Number: SqlUniqueIndexViolation or SqlUniqueConstraintViolation } } =>
                (StatusCodes.Status409Conflict, ErrorCodes.Duplicate, "Dữ liệu bị trùng với bản ghi đã có."),

            DbUpdateException { InnerException: SqlException { Number: SqlConstraintViolation } } =>
                (StatusCodes.Status409Conflict, ErrorCodes.ConstraintViolation,
                 "Thao tác vi phạm ràng buộc dữ liệu (dữ liệu liên quan đang được sử dụng hoặc không hợp lệ)."),

            BadHttpRequestException bad => (bad.StatusCode, ErrorCodes.ValidationError, "Yêu cầu không đúng định dạng."),

            OperationCanceledException when ct.IsCancellationRequested => (499, "CLIENT_CLOSED_REQUEST", null),

            _ => (StatusCodes.Status500InternalServerError, ErrorCodes.InternalError,
                  "Đã có lỗi xảy ra. Vui lòng thử lại sau."),
        };

        if (exception is AppException && status >= 500)
            logger.LogError("Request {Method} {Path} failed {Status} {Code}: {Message}",
                http.Request.Method, http.Request.Path, status, code, exception.Message);
        else if (status >= 500)
            logger.LogError(exception, "Unhandled exception on {Method} {Path}", http.Request.Method, http.Request.Path);
        else
            logger.LogInformation("Request failed {Status} {Code}: {Message}", status, code, exception.Message);

        if (status == 499) return true; // client đã hủy request, không cần ghi response

        await Problems.WriteAsync(http, status, code, detail, (exception as AppException)?.Extensions);
        return true;
    }
}
