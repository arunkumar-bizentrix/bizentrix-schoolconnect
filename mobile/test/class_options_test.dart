import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_connect/core/constants/app_constants.dart';
import 'package:school_connect/core/network/api_client.dart';
import 'package:school_connect/core/network/fetch_all_pages.dart';
import 'package:school_connect/core/storage/token_storage.dart';
import 'package:school_connect/features/auth/models/user_model.dart';
import 'package:school_connect/features/auth/providers/auth_provider.dart';
import 'package:school_connect/features/classes/models/class_model.dart';
import 'package:school_connect/features/classes/providers/class_options_provider.dart';
import 'package:school_connect/features/homework/screens/create_homework_screen.dart';

/// 25 classes served 10 per page. Page 2 repeats the last row of page 1, the
/// way an unstable server sort would, to prove the client does not show it
/// twice.
class _PagedClassesServer implements HttpClientAdapter {
  _PagedClassesServer({this.loopNext = false});

  /// Serve a `next` link that points back to page 2 forever.
  final bool loopNext;
  final List<Uri> requests = [];

  static Map<String, dynamic> _row(int i) => {
        'id': i,
        'name': 'Grade $i',
        'section': 'A',
        'academic_year': '2026-2027',
        'display_name': 'Grade $i - A (2026-2027)',
      };

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options.uri);
    Object body;
    if (options.uri.path.endsWith('/classes/')) {
      final page = int.tryParse(options.uri.queryParameters['page'] ?? '1') ?? 1;
      final rows = switch (page) {
        1 => [for (var i = 1; i <= 10; i++) _row(i)],
        2 => [for (var i = 10; i <= 19; i++) _row(i)], // 10 repeated
        _ => [for (var i = 20; i <= 25; i++) _row(i)],
      };
      String? next;
      if (loopNext) {
        next = 'http://test.local/api/v1/classes/?page=2';
      } else if (page < 3) {
        next = 'http://test.local/api/v1/classes/?academic_year=2026-2027&page=${page + 1}';
      }
      body = {'count': 25, 'next': next, 'previous': null, 'results': rows};
    } else {
      body = {'count': 0, 'next': null, 'previous': null, 'results': []};
    }
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }
}

class _Auth extends AuthNotifier {
  _Auth(ApiClient client, TokenStorage storage, UserRole role) : super(apiClient: client, tokenStorage: storage) {
    state = AuthState(user: UserModel(id: '1', email: 't@example.test', fullName: 'Priya', role: role));
  }

  @override
  Future<bool> restoreSession() async => true;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  ({ApiClient client, _PagedClassesServer server, TokenStorage storage}) setUpClient({bool loopNext = false}) {
    final storage = TokenStorage(const FlutterSecureStorage());
    final client = ApiClient(tokenStorage: storage);
    final server = _PagedClassesServer(loopNext: loopNext);
    client.dio.httpClientAdapter = server;
    return (client: client, server: server, storage: storage);
  }

  test('fetchAllPages returns all 25 classes once each, in order', () async {
    final (:client, :server, storage: _) = setUpClient();
    final classes = await fetchAllPages(
      client.dio,
      '/classes/',
      queryParameters: {'academic_year': '2026-2027'},
      fromJson: ClassModel.fromJson,
      idOf: (c) => c.id,
    );

    expect(classes, hasLength(25));
    expect(classes.map((c) => c.id).toSet(), hasLength(25));
    expect(classes.map((c) => c.id).toList(), [for (var i = 1; i <= 25; i++) i]);
    expect(server.requests, hasLength(3));
  });

  test('a next link that loops back stops instead of spinning forever', () async {
    final (:client, :server, storage: _) = setUpClient(loopNext: true);
    final classes = await fetchAllPages(
      client.dio,
      '/classes/',
      fromJson: ClassModel.fromJson,
      idOf: (c) => c.id,
    );
    expect(server.requests.length, lessThanOrEqualTo(3));
    expect(classes.map((c) => c.id).toSet().length, classes.length);
  });

  test('classOptionsProvider asks for the academic year and loads every page', () async {
    final (:client, :server, storage: _) = setUpClient();
    final container = ProviderContainer(overrides: [apiClientProvider.overrideWithValue(client)]);
    addTearDown(container.dispose);

    final sub = container.listen(classOptionsProvider('2026-2027'), (_, __) {});
    final classes = await container.read(classOptionsProvider('2026-2027').future);
    sub.close();

    expect(classes, hasLength(25));
    expect(server.requests.first.queryParameters['academic_year'], '2026-2027');
  });

  testWidgets('Create Homework offers the 25th class, which lives on page 3', (tester) async {
    final (:client, :server, :storage) = setUpClient();
    tester.view.physicalSize = const Size(430 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        authProvider.overrideWith((ref) => _Auth(client, storage, UserRole.teacher)),
      ],
      child: const MaterialApp(home: CreateHomeworkScreen()),
    ));
    await tester.pumpAndSettle();

    final classPicker = tester.widget<DropdownButton<int>>(find.byType(DropdownButton<int>).first);
    final offered = classPicker.items!.map((item) => item.value).toList();
    expect(offered, hasLength(25));
    expect(offered, contains(25), reason: 'Grade 25 is only on page 3');
    expect(offered.toSet(), hasLength(25), reason: 'the row repeated across pages is offered once');
  });
}
