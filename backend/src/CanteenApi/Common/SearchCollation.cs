namespace CanteenApi.Common;

/// <summary>
/// Collation dùng cho tìm kiếm tiếng Việt KHÔNG DẤU, không phân biệt hoa/thường.
///
/// Không dùng Vietnamese_CI_AI: collation này coi ă, â, ê, ô, ơ, ư, đ là CHỮ CÁI RIÊNG
/// (đúng bảng chữ cái tiếng Việt) nên "van" không khớp "Văn", "dong" không khớp "Đồng".
/// Latin1_General_100_CI_AI bỏ qua mọi dấu và quy đ → d (đã kiểm chứng trên SQL Server 2022):
///   "nguyen van an" ↔ "Nguyễn Văn An", "tra sua" ↔ "Trà sữa", "dong" ↔ "Đồng".
/// </summary>
public static class SearchCollation
{
    public const string AccentInsensitive = "Latin1_General_100_CI_AI";
}
