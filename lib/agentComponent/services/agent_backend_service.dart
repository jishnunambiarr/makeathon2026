import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

/// Base URL for the hackathon Node backend that mints ElevenLabs conversation tokens.
///
/// Android emulator: use `http://10.0.2.2:8787` (host machine localhost).
/// iOS simulator: `http://127.0.0.1:8787`
///
/// Run with:
/// `flutter run --dart-define=AGENT_BACKEND_URL=http://10.0.2.2:8787`
class AgentBackendService {
  AgentBackendService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const String baseUrl = String.fromEnvironment(
    'AGENT_BACKEND_URL',
    defaultValue: 'http://127.0.0.1:8787',
  );

  /// Returns the short-lived token from `POST /agent/session`.
  Future<String> fetchConversationToken() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/agent/session',
      data: <String, dynamic>{},
      options: Options(
        headers: {'content-type': 'application/json'},
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
      ),
    );
    final token = response.data?['elevenConversationToken'] as String?;
    if (token == null || token.isEmpty) {
      throw StateError('Backend response missing elevenConversationToken');
    }
    return token;
  }

  static String defaultUserId() => const Uuid().v4();
}
