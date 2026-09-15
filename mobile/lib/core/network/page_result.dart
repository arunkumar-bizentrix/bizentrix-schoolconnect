/// One page of a Django REST Framework list response.
///
/// DRF returns `{count, next, previous, results}` once pagination is on. A
/// client that reads only `results` silently shows the first 20 rows of a
/// 1000-student roll and looks like it lost the rest, so every list provider
/// goes through this and keeps the `next` link.
class PageResult<T> {
  const PageResult({
    required this.items,
    required this.nextUrl,
    required this.totalCount,
  });

  final List<T> items;

  /// Absolute URL of the next page, or null when this is the last one.
  final String? nextUrl;

  /// Total rows on the server, not just the ones loaded.
  final int totalCount;

  /// Parses either a paginated envelope or a bare list, so endpoints that are
  /// deliberately unpaginated (parent/children) keep working.
  static PageResult<T> parse<T>(
    dynamic data,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (data is List) {
      return PageResult<T>(
        items: data
            .whereType<Map<String, dynamic>>()
            .map(fromJson)
            .toList(growable: false),
        nextUrl: null,
        totalCount: data.length,
      );
    }

    final map = data as Map<String, dynamic>;
    final rows = (map['results'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(fromJson)
        .toList(growable: false);

    return PageResult<T>(
      items: rows,
      nextUrl: map['next'] as String?,
      totalCount: map['count'] is int ? map['count'] as int : rows.length,
    );
  }
}
