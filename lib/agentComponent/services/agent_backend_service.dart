import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

/// Base URL for the hackathon Node backend that mints ElevenLabs conversation tokens.
///
/// Android **emulator**: `http://10.0.2.2:8787` (host loopback only on the emulator).
/// **Physical device** (same Wi‑Fi as your PC): `http://<PC-LAN-IP>:8787` — **not**
/// `10.0.2.2` (that address does not reach your computer from a real phone).
/// iOS simulator: `http://127.0.0.1:8787`
///
/// Run with:
/// `flutter run --dart-define=AGENT_BACKEND_URL=http://10.0.2.2:8787`
class AgentBackendService {
  AgentBackendService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 30),
                sendTimeout: const Duration(seconds: 30),
              ),
            );

  final Dio _dio;

  static const String baseUrl = String.fromEnvironment(
    'AGENT_BACKEND_URL',
    defaultValue: 'http://127.0.0.1:8787',
  );

  /// Returns the short-lived token from `POST /agent/session`.
  Future<String> fetchConversationToken() async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$baseUrl/agent/session',
        data: <String, dynamic>{},
        options: Options(
          headers: {'content-type': 'application/json'},
        ),
      );
      final token = response.data?['elevenConversationToken'] as String?;
      if (token == null || token.isEmpty) {
        throw StateError('Backend response missing elevenConversationToken');
      }
      return token;
    } on DioException catch (e) {
      throw StateError(_dioErrorMessage(e));
    }
  }

  static String _dioErrorMessage(DioException e) {
    final url = baseUrl;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Agent backend timed out ($url). '
            'On a physical phone, use your PC’s Wi‑Fi IP, not 10.0.2.2 '
            '(10.0.2.2 works only on the Android emulator).';
      case DioExceptionType.connectionError:
        return 'Cannot reach agent backend ($url). '
            'From a physical device use http://<YOUR-PC-IP>:8787 on the same network. '
            'Details: ${e.message ?? e.error}';
      default:
        return 'Agent backend request failed (${e.response?.statusCode ?? e.type}): '
            '${e.message ?? e.error}';
    }
  }

  static String defaultUserId() => const Uuid().v4();
}
