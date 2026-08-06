import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shelf/shelf.dart';

import 'control_errors.dart';
import 'room_control.dart';

/// 제어 명령을 받는 HTTP 문.
///
/// 앱과 **같은 계약**이다 — `POST /api/control`, 헤더 `x-party-control`,
/// 몸통 `{command, args}`, 응답 `{ok, result}` 또는 `{ok:false, error}`.
/// 같은 CLI 가 앱과 헤드리스를 다 조종할 수 있어야 하므로 여기서 갈리면 안 된다.
///
/// 상태 코드도 앱과 맞춘다: 사용법 400 · 지금은 못 함 409 · 그 밖 500.
/// CLI 의 exit code(64/1)가 이 구분을 그대로 쓴다.
class ControlEndpoint {
  ControlEndpoint({required this.control, required this.token});

  final RoomControl control;

  /// 이 문을 지나려면 필요한 값. 비어 있으면 **문을 아예 열지 않는다** —
  /// 토큰 없는 제어 API 를 인터넷에 붙이는 것이 제일 나쁘다.
  final String token;

  /// 새 토큰 하나. 헤드리스가 처음 뜰 때 만들어 로그·파일로 알린다.
  static String newToken([Random? rng]) {
    final r = rng ?? Random.secure();
    const abc =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return [for (var i = 0; i < 32; i++) abc[r.nextInt(abc.length)]].join();
  }

  /// `RoomServer.extraRoutes` 에 그대로 물린다.
  Future<Response?> route(Request req) async {
    if (req.url.path != 'api/control') return null;
    if (token.isEmpty) {
      return _json(503, {
        'ok': false,
        'error': {'message': '제어가 꺼져 있습니다'},
      });
    }
    if (req.method != 'POST') {
      return _json(405, {
        'ok': false,
        'error': {'message': 'POST 만 받습니다'},
      });
    }
    if (req.headers['x-party-control'] != token) {
      return _json(403, {
        'ok': false,
        'error': {'message': '제어 토큰이 맞지 않습니다'},
      });
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return _json(400, {
        'ok': false,
        'error': {'message': '본문이 JSON 이 아닙니다'},
      });
    }

    try {
      final result = await control.run(
        body['command'] as String? ?? '',
        (body['args'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
      return _json(200, {'ok': true, 'result': result});
    } on ControlUsageError catch (e) {
      return _json(400, {
        'ok': false,
        'error': {'message': e.message, 'kind': 'usage'},
      });
    } on ControlFailure catch (e) {
      return _json(409, {
        'ok': false,
        'error': {'message': e.message, 'kind': 'failure'},
      });
    } catch (e) {
      return _json(500, {
        'ok': false,
        'error': {'message': '$e'},
      });
    }
  }

  static Response _json(int status, Map<String, dynamic> body) => Response(
    status,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
  );
}
