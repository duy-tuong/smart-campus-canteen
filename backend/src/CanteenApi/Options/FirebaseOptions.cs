namespace CanteenApi.Options;

/// <summary>
/// Cấu hình kết nối Firebase, đọc từ section "Firebase" trong appsettings
/// hoặc từ dotnet user-secrets / biến môi trường (Firebase__ProjectId, ...).
/// </summary>
public sealed class FirebaseOptions
{
    public const string SectionName = "Firebase";

    /// <summary>Project ID của Firebase, dùng để xác minh ID token (issuer/audience). Bắt buộc.</summary>
    public string ProjectId { get; set; } = string.Empty;

    /// <summary>URL Realtime Database, ví dụ https://&lt;project&gt;-default-rtdb.asia-southeast1.firebasedatabase.app</summary>
    public string DatabaseUrl { get; set; } = string.Empty;

    /// <summary>
    /// Đường dẫn tới file service account JSON. KHÔNG đặt file này trong repo;
    /// cấu hình qua user-secrets (dev) hoặc biến môi trường (deploy).
    /// </summary>
    public string CredentialPath { get; set; } = string.Empty;

    /// <summary>
    /// Web API key (khóa công khai của app, có trong firebase_options.dart).
    /// Chỉ dùng cho endpoint /api/dev/token để lấy ID token khi test API.
    /// </summary>
    public string WebApiKey { get; set; } = string.Empty;
}
