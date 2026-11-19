import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

/// Error dari server berformat {"error": kode, "message": teks} (desain §5).
class ApiError implements Exception {
  ApiError(this.status, this.code, this.message);

  final int status;
  final String code, message;

  @override
  String toString() => '$code: $message';
}

/// Klien API mobile /api/v1. Halaman error non-JSON (mis. 502 dari proxy) muncul sebagai FormatException
/// dan diperlakukan seperti gangguan jaringan oleh SyncEngine.
class Api {
  Api(this.base, {http.Client? client, this.token}) : _client = client ?? http.Client();

  final String base;
  final http.Client _client;
  String? token;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-App-Version': appVersion,
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> _send(String path, [Object? body]) async {
    final uri = Uri.parse('$base$path');
    final res = await (body == null
            ? _client.get(uri, headers: _headers)
            : _client.post(uri, headers: _headers, body: jsonEncode(body)))
        .timeout(const Duration(seconds: 30));
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw ApiError(res.statusCode, '${data['error'] ?? 'http_${res.statusCode}'}', '${data['message'] ?? ''}');
    }
    return data;
  }

  /// POST /device/activate (tanpa token).
  Future<Map<String, dynamic>> activate(String code) => _send('/device/activate', {'code': code, 'app_version': appVersion});

  /// GET /sync/master?version=…
  Future<Map<String, dynamic>> master(int version) => _send('/sync/master?version=$version');

  /// POST /sync/push, maksimal 100 event.
  Future<Map<String, dynamic>> push(List<Map<String, Object?>> events, int pendingAfter) =>
      _send('/sync/push', {'pending_after': pendingAfter, 'events': events});
}
