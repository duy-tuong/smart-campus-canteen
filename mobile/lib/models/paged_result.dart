/// Một trang dữ liệu từ API: { items, page, pageSize, totalCount, totalPages, hasNext }.
class PagedResult<T> {
  const PagedResult({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.totalCount,
    required this.totalPages,
    required this.hasNext,
  });

  factory PagedResult.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic>) itemFromJson) {
    final items = (json['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(itemFromJson)
        .toList();
    final page = (json['page'] as num?)?.toInt() ?? 1;
    final totalPages = (json['totalPages'] as num?)?.toInt() ?? 1;
    return PagedResult(
      items: items,
      page: page,
      pageSize: (json['pageSize'] as num?)?.toInt() ?? items.length,
      totalCount: (json['totalCount'] as num?)?.toInt() ?? items.length,
      totalPages: totalPages,
      hasNext: json['hasNext'] as bool? ?? page < totalPages,
    );
  }

  final List<T> items;
  final int page;
  final int pageSize;
  final int totalCount;
  final int totalPages;
  final bool hasNext;
}
