namespace CanteenApi.Common;

/// <summary>Dựng URL tuyệt đối cho file tĩnh (ảnh) theo host của request hiện tại.</summary>
public interface IPublicUrlBuilder
{
    string? Build(string? relativePath);
}

public sealed class PublicUrlBuilder(IHttpContextAccessor accessor) : IPublicUrlBuilder
{
    public string? Build(string? relativePath)
    {
        var request = accessor.HttpContext?.Request;
        return request is null ? relativePath : UrlHelper.ToAbsolute(request, relativePath);
    }
}
