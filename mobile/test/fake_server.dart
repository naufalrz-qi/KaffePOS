import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures.dart';

const serverTime = '2026-11-19T03:00:00.000Z';

http.Response _json(Object body, int status) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

/// Server palsu untuk /device/activate, /sync/push, dan /sync/master (kontrak desain §5).
class FakeServer {
  int masterVersion = 5;
  Map<String, dynamic> snapshot = snapshotJson();
  String Function(Map<String, dynamic> event) statusFor = (_) => 'ok';
  int? failStatus;
  bool offline = false;
  int snapshotsSent = 0;
  final pushed = <Map<String, dynamic>>[];
  final pushBatchSizes = <int>[];
  final pendingAfter = <int>[];
  final requests = <http.Request>[];

  late final client = MockClient((request) async {
    requests.add(request);
    if (offline) throw http.ClientException('jaringan putus');
    if (failStatus != null) {
      return _json({'error': failStatus == 401 ? 'device_revoked' : 'server_error', 'message': 'gagal'}, failStatus!);
    }
    final path = request.url.path;
    if (path.endsWith('/device/activate')) {
      return (jsonDecode(request.body) as Map)['code'] == 'K7F3X9QA'
          ? _json({
              'token': 'token-uji',
              'device': {'id': 'd1', 'number': 3},
              'outlet': {'id': 'o1', 'code': 'GRB01', 'name': 'Gerobak Sudirman'},
            }, 200)
          : _json({'error': 'invalid_code', 'message': 'Kode aktivasi salah, kedaluwarsa, atau sudah dipakai'}, 400);
    }
    if (path.endsWith('/sync/push')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final events = (body['events'] as List).cast<Map<String, dynamic>>();
      pushed.addAll(events);
      pushBatchSizes.add(events.length);
      pendingAfter.add(body['pending_after'] as int);
      return _json({
        'results': [
          for (final e in events)
            {
              'id': e['id'],
              'status': statusFor(e),
              if (statusFor(e) == 'rejected' || statusFor(e) == 'retry') 'reason': 'uji: ${statusFor(e)}',
            },
        ],
        'server_time': serverTime,
        'master_version': masterVersion,
      }, 200);
    }
    final version = int.parse(request.url.queryParameters['version']!);
    if (version == masterVersion) return _json({'changed': false, 'version': version, 'server_time': serverTime}, 200);
    snapshotsSent++;
    return _json({'changed': true, 'version': masterVersion, 'server_time': serverTime, 'snapshot': snapshot}, 200);
  });
}
