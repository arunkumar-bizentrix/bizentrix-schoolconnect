import 'package:dio/dio.dart';

import 'page_result.dart';

/// Loads every page of a paginated list endpoint.
///
/// For pickers that must offer *all* of something - a teacher's classes, the
/// school's subjects - where showing only the first page silently hides
/// choices. Browsing screens should keep using "load more" instead.
///
/// Rows are de-duplicated by [idOf], keeping first-seen order, so a row the
/// server repeats across a page boundary appears once. Following stops if the
/// server hands back a `next` link already visited, or after [maxPages], so a
/// misbehaving API cannot spin the app forever.
Future<List<T>> fetchAllPages<T>(
  Dio dio,
  String path, {
  Map<String, dynamic>? queryParameters,
  required T Function(Map<String, dynamic>) fromJson,
  required Object Function(T) idOf,
  int maxPages = 100,
}) async {
  final byId = <Object, T>{};

  void addAll(List<T> items) {
    for (final item in items) {
      byId.putIfAbsent(idOf(item), () => item);
    }
  }

  final first = await dio.get(path, queryParameters: queryParameters);
  var page = PageResult.parse(first.data, fromJson);
  addAll(page.items);

  final visited = <String>{};
  var pages = 1;
  while (page.nextUrl != null && pages < maxPages && visited.add(page.nextUrl!)) {
    final response = await dio.getUri(Uri.parse(page.nextUrl!));
    page = PageResult.parse(response.data, fromJson);
    addAll(page.items);
    pages++;
  }

  return byId.values.toList(growable: false);
}
