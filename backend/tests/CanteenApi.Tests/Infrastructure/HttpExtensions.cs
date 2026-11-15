using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CanteenApi.Tests.Infrastructure;

/// <summary>Tiện ích gọi API và đọc kết quả (JSON camelCase, enum dạng chuỗi như app thật).</summary>
public static class HttpExtensions
{
    public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    public static async Task<T> ReadAsAsync<T>(this HttpResponseMessage response, HttpStatusCode expected = HttpStatusCode.OK)
    {
        await response.ShouldHaveStatusAsync(expected);
        return (await response.Content.ReadFromJsonAsync<T>(Json))!;
    }

    public static async Task ShouldHaveStatusAsync(this HttpResponseMessage response, HttpStatusCode expected)
    {
        if (response.StatusCode != expected)
        {
            var body = await response.Content.ReadAsStringAsync();
            Assert.Fail($"Mong đợi {(int)expected} {expected} nhưng nhận {(int)response.StatusCode}: {body}");
        }
    }

    /// <summary>Kiểm tra response là ProblemDetails với đúng HTTP status và mã lỗi "code"; trả về nội dung.</summary>
    public static async Task<JsonElement> ShouldBeProblemAsync(this HttpResponseMessage response, HttpStatusCode status, string code)
    {
        await response.ShouldHaveStatusAsync(status);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        var problem = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
        Assert.Equal(code, problem.GetProperty("code").GetString());
        Assert.True(problem.TryGetProperty("traceId", out _), "ProblemDetails phải có traceId");
        return problem;
    }

    public static Task<HttpResponseMessage> PostJsonAsync<T>(this HttpClient client, string url, T body) =>
        client.PostAsJsonAsync(url, body, Json);

    public static Task<HttpResponseMessage> PutJsonAsync<T>(this HttpClient client, string url, T body) =>
        client.PutAsJsonAsync(url, body, Json);

    public static Task<HttpResponseMessage> PatchJsonAsync<T>(this HttpClient client, string url, T body) =>
        client.PatchAsJsonAsync(url, body, Json);

    /// <summary>Gửi file ảnh dạng multipart (field "file").</summary>
    public static Task<HttpResponseMessage> UploadAsync(this HttpClient client, string url, byte[] content, string fileName)
    {
        var form = new MultipartFormDataContent();
        var file = new ByteArrayContent(content);
        file.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("image/png");
        form.Add(file, "file", fileName);
        return client.PostAsync(url, form);
    }

    /// <summary>PNG 1×1 hợp lệ.</summary>
    public static byte[] TinyPng() => Convert.FromBase64String(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC");
}
