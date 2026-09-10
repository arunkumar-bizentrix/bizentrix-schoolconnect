import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_constants.dart';
import '../errors/failures.dart';
import '../storage/token_storage.dart';
import 'api_endpoints.dart';

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
          final is401 = error.response?.statusCode == 401;
          final path = error.requestOptions.path;
          final isAuthEndpoint = path.contains('/auth/token/');

          if (is401 && !isAuthEndpoint) {
            final refreshToken = await tokenStorage.getRefreshToken();
            if (refreshToken != null && refreshToken.isNotEmpty) {
              try {
                // Use a separate Dio instance without interceptors to prevent circular refresh calls
                final refreshDio = Dio(
                  BaseOptions(
                    baseUrl: dio.options.baseUrl,
                    connectTimeout: AppConstants.connectTimeout,
                    receiveTimeout: AppConstants.receiveTimeout,
                    headers: {
                      'Content-Type': 'application/json',
                      'Accept': 'application/json',
                    },
                  ),
                );

                final refreshResponse = await refreshDio.post(
                  ApiEndpoints.refreshToken,
                  data: {'refresh': refreshToken},
                );

                if (refreshResponse.statusCode == 200 && refreshResponse.data != null) {
                  final newAccess = refreshResponse.data['access']?.toString();
                  final newRefresh = refreshResponse.data['refresh']?.toString();

                  if (newAccess != null && newAccess.isNotEmpty) {
                    await tokenStorage.saveTokens(
                      accessToken: newAccess,
                      refreshToken: newRefresh ?? refreshToken,
                    );

                    // Re-dispatch the failed request with the new access token
                    final originalOptions = error.requestOptions;
                    originalOptions.headers['Authorization'] = 'Bearer $newAccess';

                    final retryResponse = await dio.fetch(originalOptions);
                    return handler.resolve(retryResponse);
                  }
                }
              } catch (_) {
                await tokenStorage.clearAll();
              }
            }
          }
          // Automatic failover between Wi-Fi LAN IP and adb reverse proxy (127.0.0.1)
          final isConnectionError = error.type == DioExceptionType.connectionError ||
              error.type == DioExceptionType.connectionTimeout;
          final alreadyRetried = error.requestOptions.extra['retried_fallback'] == true;

          if (isConnectionError && !alreadyRetried) {
            final currentBase = dio.options.baseUrl;
            final isLan = currentBase.contains('192.168.');
            final alternateBase = isLan
                ? AppConstants.fallbackBaseUrl
                : AppConstants.defaultBaseUrl;

            if (currentBase != alternateBase) {
              try {
                final options = error.requestOptions;
                options.extra['retried_fallback'] = true;
                options.baseUrl = alternateBase;
                dio.options.baseUrl = alternateBase;
                final response = await dio.fetch(options);
                return handler.resolve(response);
              } catch (_) {
                // If alternate also fails, proceed to normal error handling
              }
            }
          }

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
          return const NetworkFailure('Unable to connect to the server. Please check your network or server URL.');
        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode;
          final responseData = error.response?.data;

          if (statusCode == 401) {
            return const AuthFailure('Session expired or unauthorized. Please log in.');
          }
          if (statusCode == 403) {
            return const AuthFailure('Access denied. You do not have permission for this action.');
          }
          if (statusCode == 404) {
            return const ServerFailure('Requested resource not found.', 404);
          }
          if (statusCode != null && statusCode >= 500) {
            return ServerFailure('Server error. Please try again later.', statusCode);
          }

          String message = 'Validation failed.';
          if (responseData is Map<String, dynamic>) {
            if (responseData.containsKey('detail')) {
              message = responseData['detail'].toString();
            } else if (responseData.containsKey('message')) {
              message = responseData['message'].toString();
            } else {
              // Parse DRF validation error map (e.g. {"name": ["This field is required."]})
              final fieldErrors = <String>[];
              responseData.forEach((key, val) {
                if (val is List) {
                  fieldErrors.add('$key: ${val.join(", ")}');
                } else {
                  fieldErrors.add('$key: $val');
                }
              });
              if (fieldErrors.isNotEmpty) {
                message = fieldErrors.join(' | ');
              }
            }
          } else if (responseData is String && responseData.isNotEmpty) {
            message = responseData;
          }
          return ServerFailure(message, statusCode);
        default:
          return ServerFailure(error.message ?? 'Unexpected error occurred');
      }
    }
    return ServerFailure(error.toString());
  }
}
