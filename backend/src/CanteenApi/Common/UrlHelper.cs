namespace CanteenApi.Common;

public static class UrlHelper
{
    /// <summary>
    /// Đổi đường dẫn tương đối lưu trong database ("/uploads/foods/a.jpg") thành URL tuyệt đối
    /// theo đúng host mà client đang gọi. Ví dụ Android Emulator gọi http://10.0.2.2:5265
    /// sẽ nhận http://10.0.2.2:5265/uploads/foods/a.jpg — tải ảnh được ngay.
    /// </summary>
    public static string? ToAbsolute(HttpRequest request, string? path)
    {
        if (string.IsNullOrWhiteSpace(path)) return null;
        if (Uri.TryCreate(path, UriKind.Absolute, out var absolute) && absolute.Scheme.StartsWith("http"))
            return path;

        return $"{request.Scheme}://{request.Host}{request.PathBase}/{path.TrimStart('/')}";
    }
}
