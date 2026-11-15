using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using CanteenApi.Options;
using CanteenApi.Services.Firebase;
using Microsoft.Extensions.Options;

namespace CanteenApi.Services;

/// <summary>
/// Truy cập Firebase Realtime Database qua REST API.
///
/// Thư viện FirebaseAdmin cho .NET KHÔNG hỗ trợ Realtime Database, nên backend gọi
/// trực tiếp REST endpoint: {DatabaseUrl}/{path}.json kèm OAuth2 access token
/// sinh từ service account. Token admin bỏ qua Security Rules → chỉ backend được ghi.
/// </summary>
public sealed class FirebaseDbService
{
    /// <summary>JSON camelCase để khớp với dữ liệu Flutter đọc từ RTDB.</summary>
    public static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    private readonly HttpClient _http;
    private readonly FirebaseCredentialProvider _credentials;
    private readonly string _baseUrl;

    public FirebaseDbService(HttpClient http, FirebaseCredentialProvider credentials, IOptions<FirebaseOptions> options)
    {
        _http = http;
        _credentials = credentials;
        _baseUrl = options.Value.DatabaseUrl.TrimEnd('/');
    }

    /// <summary>Đọc dữ liệu tại <paramref name="path"/>. Trả về default nếu node không tồn tại.</summary>
    public async Task<T?> GetAsync<T>(string path, string? query = null, CancellationToken ct = default)
    {
        using var request = await CreateRequestAsync(HttpMethod.Get, path, query, ct);
        using var response = await _http.SendAsync(request, ct);
        await EnsureSuccessAsync(response, ct);
        return await response.Content.ReadFromJsonAsync<T>(JsonOptions, ct);
    }

    /// <summary>
    /// Truy vấn có lọc, ví dụ QueryAsync&lt;Order&gt;("orders", "userId", uid).
    /// Cần khai báo ".indexOn" cho trường tương ứng trong Security Rules.
    /// </summary>
    public Task<Dictionary<string, T>?> QueryAsync<T>(string path, string orderBy, string equalTo, CancellationToken ct = default)
    {
        var query = $"orderBy={Uri.EscapeDataString(JsonSerializer.Serialize(orderBy))}"
                  + $"&equalTo={Uri.EscapeDataString(JsonSerializer.Serialize(equalTo))}";
        return GetAsync<Dictionary<string, T>>(path, query, ct);
    }

    /// <summary>Ghi đè toàn bộ node (HTTP PUT).</summary>
    public Task SetAsync<T>(string path, T value, CancellationToken ct = default)
        => SendJsonAsync(HttpMethod.Put, path, value, ct);

    /// <summary>Cập nhật một phần các trường của node (HTTP PATCH).</summary>
    public Task UpdateAsync<T>(string path, T value, CancellationToken ct = default)
        => SendJsonAsync(HttpMethod.Patch, path, value, ct);

    /// <summary>Thêm phần tử mới với khóa tự sinh (HTTP POST, tương đương push()). Trả về khóa mới.</summary>
    public async Task<string> PushAsync<T>(string path, T value, CancellationToken ct = default)
    {
        using var response = await SendJsonCoreAsync(HttpMethod.Post, path, value, ct);
        var result = await response.Content.ReadFromJsonAsync<PushResult>(JsonOptions, ct);
        return result?.Name ?? throw new InvalidOperationException("Firebase không trả về khóa mới.");
    }

    /// <summary>Xóa node (HTTP DELETE).</summary>
    public async Task DeleteAsync(string path, CancellationToken ct = default)
    {
        using var request = await CreateRequestAsync(HttpMethod.Delete, path, null, ct);
        using var response = await _http.SendAsync(request, ct);
        await EnsureSuccessAsync(response, ct);
    }

    private async Task SendJsonAsync<T>(HttpMethod method, string path, T value, CancellationToken ct)
    {
        using var _ = await SendJsonCoreAsync(method, path, value, ct);
    }

    private async Task<HttpResponseMessage> SendJsonCoreAsync<T>(HttpMethod method, string path, T value, CancellationToken ct)
    {
        using var request = await CreateRequestAsync(method, path, null, ct);
        request.Content = JsonContent.Create(value, options: JsonOptions);
        var response = await _http.SendAsync(request, ct);
        await EnsureSuccessAsync(response, ct);
        return response;
    }

    private async Task<HttpRequestMessage> CreateRequestAsync(HttpMethod method, string path, string? query, CancellationToken ct)
    {
        var url = $"{_baseUrl}/{path.Trim('/')}.json";
        if (!string.IsNullOrEmpty(query)) url += "?" + query;

        if (string.IsNullOrEmpty(_baseUrl))
            throw new InvalidOperationException("Chưa cấu hình Firebase:DatabaseUrl (xem README).");

        var token = await _credentials.RtdbToken.GetAccessTokenForRequestAsync(cancellationToken: ct);
        var request = new HttpRequestMessage(method, url);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return request;
    }

    private static async Task EnsureSuccessAsync(HttpResponseMessage response, CancellationToken ct)
    {
        if (response.IsSuccessStatusCode) return;
        var body = await response.Content.ReadAsStringAsync(ct);
        throw new HttpRequestException(
            $"Firebase RTDB trả về lỗi {(int)response.StatusCode}: {body}", null, response.StatusCode);
    }

    private sealed record PushResult(string Name);
}
