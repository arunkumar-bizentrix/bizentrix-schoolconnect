import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_constants.dart';
import '../errors/failures.dart';
import '../storage/token_storage.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final tokenStorage = ref.watch(tokenStorageProvider);
  return ApiClient(tokenStorage: tokenStorage);
});

class ApiClient {
  final TokenStorage tokenStorage;
  late final Dio dio;

  ApiClient({
    required this.tokenStorage,
    String? baseUrl,
  }) {
    dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? AppConstants.defaultBaseUrl,
        connectTimeout: AppConstants.connectTimeout,
        receiveTimeout: AppConstants.receiveTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Auth & Logging Interceptor
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await tokenStorage.getAccessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          // Future extension: Handle 401 automatic token refresh here
          return handler.next(error);
        },
      ),
    );
  }

  /// Handle Dio exceptions cleanly and transform into Failure objects
  Failure handleError(dynamic error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return const NetworkFailure('Unable to connect to the server. Please check your network.');
        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode;
          final responseData = error.response?.data;
          
          if (statusCode == 401) {
            return const AuthFailure('Session expired or unauthorized. Please log in.');
          }

          String message = 'Server returned an error';
          if (responseData is Map<String, dynamic>) {
            if (responseData.containsKey('detail')) {
              message = responseData['detail'].toString();
            } else if (responseData.containsKey('message')) {
              message = responseData['message'].toString();
            }
          }
          return ServerFailure(message, statusCode);
        default:
          return ServerFailure(error.message ?? 'Unexpected error occurred');
      }
    }
    return ServerFailure(error.toString());
  }
}
