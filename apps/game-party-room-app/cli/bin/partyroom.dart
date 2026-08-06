import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 파티룸 CLI.
///
/// 이 앱의 호스트 화면은 오래도록 **자동화로 검증할 수 없었다** — 판을
/// 시작하거나 상태를 확인할 길이 화면 버튼뿐이라, 에이전트는 스크린샷을 찍고
/// 좌표를 눌러야 했고 창이 다른 Space 에 있으면 캡처조차 못 했다.
/// (`docs/app-interop-contract.md`: "정식 CLI 가 있는데 GUI 좌표·메뉴 클릭으로
/// 같은 기능 수행" 은 금지 우회다.)
///
/// 이 CLI 는 로직을 따로 갖지 않는다. 떠 있는 앱의 제어 API 를 부르고, 그
/// API 는 GUI 와 **같은 Core**(ControlService)를 지난다.
///
/// 출력 규약(계약 3조): `--json` 이면 `{"ok":true,"result":…}` /
/// 실패는 `{"ok":false,"error":{"message":…}}`. exit 0 성공 · 64 사용법 ·
/// 그 밖 비영.
const version = '1.0.0';

const _appSupport = 'Library/Application Support/PartyRoom';

File _stateFile() => File('${_home()}/$_appSupport/state.json');
File _tokenFile() => File('${_home()}/$_appSupport/control.json');

String _home() => Platform.environment['HOME'] ?? '.';

void main(List<String> argv) async {
  final json = argv.contains('--json');
  final args = argv.where((a) => a != '--json').toList();
  if (args.isEmpty || args.first == '--help' || args.first == 'help') {
    stdout.write(_usage);
    exit(args.isEmpty ? 64 : 0);
  }

  try {
    final result = await _dispatch(args);
    if (json) {
      stdout.writeln(jsonEncode({'ok': true, 'result': result}));
    } else {
      stdout.writeln(_human(args.first, result));
    }
    exit(0);
  } on _Usage catch (e) {
    _fail(e.message, json, 64);
  } on _Failure catch (e) {
    _fail(e.message, json, e.code);
  }
}

Never _fail(String message, bool json, int code) {
  if (json) {
    stdout.writeln(
      jsonEncode({
        'ok': false,
        'error': {'message': message},
      }),
    );
  } else {
    stderr.writeln('오류: $message');
  }
  exit(code);
}

/// 이 CLI 가 아는 명령 전부.
///
/// capabilities 와 dispatch 가 각자 목록을 들면 갈라진다 — 계약 문서가 기록한
/// 실제 사고가 "서브커맨드 소실"(등록은 돼 있는데 부르면 unknown)이다.
/// 두 곳이 이 하나를 읽는다.
const _commands = <String, String>{
  'state': '마지막으로 게시된 앱 상태(앱이 꺼져 있어도 답한다)',
  'status': '떠 있는 앱의 지금 상태',
  'games': '종목 목록과 시작 가능 여부',
  'players': '참가자 목록',
  'rooms': '방 목록 — 이름·인원·진행 상태',
  'sections': '대화·자료 칸 목록',
  'start': '판 시작 — start <게임id>',
  'end': '진행 중인 판 끝내기',
  'restart': '같은 종목 한 판 더 (구슬·사다리)',
  'chat': '호스트로 한마디',
  'kick': '참가자 내보내기 — kick <태그>',
  'marble': '구슬 룰렛 — marble launch|skip',
  'ladder': '사다리타기 — ladder next|all',
  'mafia': '마피아 진행 — mafia night|day|vote|close',
  'liar': '라이어 진행 — liar vote|close',
  'tunnel': '인터넷 개방 — tunnel start|stop|recheck',
  'relay': '밖에 있는 사람 들이기 — relay [status]|set <주소|off>|start|stop',
  'room':
      '방 — room new <이름>|use <토큰>|open|close|rename <이름>|'
      'pin <4자리|off>|clear --yes|delete --yes|prune|addresses|address <n>',
  'files': '자료 — files list|share <경로>|clear|remove <id>',
  'mc': '사회자 연결 시험',
  'capabilities': '기계가 읽는 자기소개',
  'version': '버전',
};

Future<Map<String, dynamic>> _dispatch(List<String> args) async {
  final cmd = args.first;
  final rest = args.skip(1).toList();
  if (!_commands.containsKey(cmd)) {
    throw _Usage(
      '모르는 명령: $cmd. Run `partyroom help` for valid commands. '
      'Example: partyroom state --json',
    );
  }

  switch (cmd) {
    case 'capabilities':
      return _capabilities();

    case 'version':
      return {'version': version};

    // 앱이 꺼져 있어도 마지막 상태는 답한다 — "왜 안 켜졌나" 도 질문이다.
    case 'state':
      final f = _stateFile();
      if (!f.existsSync()) {
        throw _Failure('상태 파일이 없습니다 — 파티룸을 한 번도 켜지 않았습니다');
      }
      final age = DateTime.now().difference(f.lastModifiedSync());
      return {
        ...(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>),
        'staleSeconds': age.inSeconds,
        'live': await _alive(),
      };

    case 'status':
      return _call('status');
    case 'games':
      return _call('games');
    case 'players':
      return _call('players');
    case 'rooms':
      return _call('rooms');
    case 'sections':
      return _call('sections');

    case 'chat':
      if (rest.isEmpty) throw _Usage('chat <말> [--section <id>]');
      return _call('chat', {
        'text': _positional(rest).join(' '),
        'section': ?_opt(rest, '--section'),
      });

    case 'start':
      if (rest.isEmpty) throw _Usage('start <게임id> [옵션]');
      final game = _positional(rest).first;
      return _call('start', {
        'game': game,
        if (_opt(rest, '--outcomes') != null)
          'outcomes': _opt(rest, '--outcomes')!.split(','),
        if (_opt(rest, '--question') != null)
          'question': _opt(rest, '--question'),
        if (_opt(rest, '--options') != null)
          'options': _opt(rest, '--options')!.split(','),
      });

    case 'end':
      return _call('end');

    case 'kick':
      if (rest.isEmpty) throw _Usage('kick <태그>');
      return _call('kick', {'tag': _positional(rest).first});

    case 'marble':
      if (rest.isEmpty) throw _Usage('marble <launch|skip>');
      return _call('marble', {'action': _positional(rest).first});

    case 'ladder':
      if (rest.isEmpty) throw _Usage('ladder <next|all>');
      return _call('ladder', {'action': _positional(rest).first});

    case 'mafia':
      if (rest.isEmpty) throw _Usage('mafia <night|day|vote|close>');
      return _call('mafia', {'action': _positional(rest).first});

    case 'liar':
      if (rest.isEmpty) throw _Usage('liar <vote|close>');
      return _call('liar', {'action': _positional(rest).first});

    case 'restart':
      return _call('restart');

    case 'tunnel':
      if (rest.isEmpty) throw _Usage('tunnel <start|stop|recheck>');
      return _call('tunnel', {'action': _positional(rest).first});

    // 밖에 있는 사람을 들이는 길. 인자 없이 부르면 상태를 준다 —
    // "지금 켜져 있나, 방 코드가 뭔가" 가 제일 자주 묻는 것이다.
    case 'relay':
      final pos = _positional(rest);
      if (pos.isEmpty) return _call('relay', {'action': 'status'});
      if (pos.first == 'set') {
        if (pos.length < 2) throw _Usage('relay set <주소|off>');
        return _call('relay', {'action': 'set', 'url': pos[1]});
      }
      return _call('relay', {'action': pos.first});

    case 'mc':
      return _call('mc', {'action': 'probe'});

    case 'room':
      if (rest.isEmpty) {
        throw _Usage('room <reset|prune|addresses|address <n>|refresh>');
      }
      final pos = _positional(rest);
      return _call('room', {
        'action': pos.first,
        if (pos.length > 1) 'index': int.tryParse(pos[1]),
        // new/rename 은 이름, use/open/close/delete 는 토큰을 받는다.
        if (pos.length > 1 && (pos.first == 'new' || pos.first == 'rename'))
          'name': pos.skip(1).join(' '),
        // pin 은 값과 대상이 둘 다 필요할 수 있다: `room pin 4821 [토큰]`.
        if (pos.length > 1 && pos.first == 'pin') 'pin': pos[1],
        if (pos.length > 2 && pos.first == 'pin') 'token': pos[2],
        if (pos.length > 1 &&
            const [
              'use',
              'open',
              'close',
              'clear',
              'delete',
            ].contains(pos.first))
          'token': pos[1],
        // 방 초기화는 참가자·진행 상황을 전부 지운다 — 실수로 지나가면 안 된다.
        if (rest.contains('--yes')) 'confirm': true,
      });

    case 'files':
      if (rest.isEmpty) throw _Usage('files <list|share|clear|remove>');
      final fpos = _positional(rest);
      return _call('files', {
        'action': fpos.first,
        if (fpos.length > 1 && fpos.first == 'share')
          'paths': fpos.skip(1).toList(),
        if (fpos.length > 1 && fpos.first == 'remove') 'id': fpos[1],
        'section': ?_opt(rest, '--section'),
      });

    default:
      throw _Usage(
        '모르는 명령: $cmd. Run `partyroom help` for valid commands. '
        'Example: partyroom state --json',
      );
  }
}

/// 이 CLI 가 아는 플래그 전부.
///
/// 모르는 플래그를 **조용히 버리면 안 된다**. `_positional` 은 `--x` 를
/// 만나면 값까지 건너뛰므로, `room pin --pin 4907` 처럼 부르면 비밀번호가
/// 통째로 사라진 채 명령이 성공한다 — 자물쇠를 걸려던 사람이 안 걸린 방을
/// 잠갔다고 믿게 된다. 실제로 그렇게 당했다.
/// 뒤에 값이 따라오는 플래그.
const _valueFlags = {'--options', '--outcomes', '--question', '--section'};

/// 값 없이 서 있는 플래그. 뒤 토큰을 먹으면 안 된다 —
/// `room delete --yes W7MNSG` 에서 토큰이 사라진다.
const _boolFlags = {'--help', '--json', '--yes'};

List<String> _positional(List<String> args) {
  final out = <String>[];
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (!a.startsWith('--')) {
      out.add(a);
      continue;
    }
    if (_boolFlags.contains(a)) continue;
    if (_valueFlags.contains(a)) {
      i++; // 값도 건너뛴다
      continue;
    }
    throw _Usage(
      '모르는 옵션: $a '
      '(아는 것: ${([..._boolFlags, ..._valueFlags].toList()..sort()).join(" ")}). '
      'Run `partyroom help`. Example: partyroom state --json',
    );
  }
  return out;
}

String? _opt(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i < 0 || i + 1 >= args.length) return null;
  return args[i + 1];
}

/// 떠 있는 앱을 부른다. 앱이 없으면 그 사실을 사람 말로 알린다.
Future<Map<String, dynamic>> _call(
  String command, [
  Map<String, dynamic> args = const {},
]) async {
  final token = _token();
  final port = _port();
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final req = await client.post('127.0.0.1', port, '/api/control');
    req.headers.contentType = ContentType.json;
    req.headers.set('x-party-control', token);
    req.write(jsonEncode({'command': command, 'args': args}));
    final res = await req.close().timeout(const Duration(seconds: 10));
    final body = jsonDecode(await res.transform(utf8.decoder).join());
    if (body is! Map || body['ok'] != true) {
      String? msg;
      if (body is Map) {
        final err = body['error'];
        if (err is Map) msg = err['message'] as String?;
      }
      // 사용법 오류는 exit 64 로 갈라 준다.
      throw _Failure(
        msg ?? 'HTTP ${res.statusCode}',
        code: res.statusCode == 400 ? 64 : 1,
      );
    }
    return (body['result'] as Map).cast<String, dynamic>();
  } on SocketException {
    throw _Failure('파티룸이 실행 중이 아닙니다 (포트 $port)');
  } on TimeoutException {
    // 앱이 떠 있는데 안 답하는 경우 — 스택을 뱉지 말고 사람 말로.
    throw _Failure('파티룸이 응답하지 않습니다 (포트 $port). 앱이 바쁜지 확인하세요');
  } finally {
    client.close(force: true);
  }
}

String _token() {
  final f = _tokenFile();
  if (!f.existsSync()) {
    throw _Failure('제어 토큰이 없습니다 — 파티룸을 한 번 실행하세요');
  }
  return (jsonDecode(f.readAsStringSync()) as Map)['token'] as String;
}

/// 상태 파일이 알려주는 포트를 쓴다 — 8765 가 막혀 옆으로 비켜 앉았을 수 있다.
int _port() {
  try {
    final j = jsonDecode(_stateFile().readAsStringSync()) as Map;
    final p = (j['room'] as Map?)?['port'];
    if (p is int) return p;
  } catch (_) {}
  return 8765;
}

Future<bool> _alive() async {
  try {
    await _call('status');
    return true;
  } catch (_) {
    return false;
  }
}

Map<String, dynamic> _capabilities() => {
  'name': 'partyroom',
  'version': version,
  'cli': Platform.resolvedExecutable.endsWith('dart')
      ? 'partyroom'
      : Platform.resolvedExecutable,
  'commands': [
    for (final e in _commands.entries)
      {'name': e.key, 'summary': e.value, 'json': true},
  ],
  // 게임마다 받는 action(marble launch, ladder next …)은 앱이 정본으로 들고
  // 있다. 여기 베껴 두면 갈라지므로 어디서 물어보는지만 적는다.
  'discover': {
    'gameActions': 'partyroom games --json',
    'roomActions': 'partyroom room --json',
  },
  'state': [
    {'path': '~/$_appSupport/state.json', 'what': '방·참가자·판·네트워크 상태'},
    {'path': '~/$_appSupport/control.json', 'what': '제어 토큰(600)'},
  ],
  'health': {
    'command': 'partyroom state --json',
    'freshness': '~/$_appSupport/state.json',
  },
};

// ---------------------------------------------------------------------------
// JSON 경계 캐스트
//
// `_call` 이 돌려주는 result 는 Map<String, dynamic> 이지만, 그 안의 목록
// 원소·중첩 객체는 여전히 dynamic 이다. 그대로 `x['token']` 을 치면
// avoid_dynamic_calls 가 나고, 응답 모양이 바뀌면 컴파일은 통과한 채
// 사용자가 명령을 친 순간에야 터진다.
//
// 여기서 한 번 Map 으로 고정하면 (1) 린트가 사라지고 (2) 캐스트 실패 시
// TypeError 스택 대신 사람 말 오류가 나간다. 조용히 null 로 넘기지 않는다.
// ---------------------------------------------------------------------------

/// 앱 응답의 객체 하나를 Map 으로 고정한다. 실패하면 사람 말 오류.
Map<String, dynamic> _requireMap(Object? value, String where) {
  if (value is Map<String, dynamic>) return value;
  // jsonDecode 는 종종 Map<dynamic, dynamic> 을 준다 — 키만 String 이면 받는다.
  if (value is Map) return Map<String, dynamic>.from(value);
  throw _Failure('앱 응답을 이해하지 못했습니다 ($where): 객체가 아닙니다');
}

/// null 은 허용하고, 값이 있으면 객체로 강제한다.
Map<String, dynamic>? _optionalMap(Object? value, String where) {
  if (value == null) return null;
  return _requireMap(value, where);
}

/// 목록의 각 원소를 객체로 캐스팅한다. null/누락은 빈 목록(기존 `?? const []`).
///
/// `_human` 이 `for (final x in list)` 로 dynamic 을 헤집던 구멍 — 여기서
/// 한 번 Map 으로 고정하면 avoid_dynamic_calls 가 사라진다.
List<Map<String, dynamic>> _mapList(Object? value, String where) {
  if (value == null) return const [];
  if (value is! List) {
    throw _Failure('앱 응답을 이해하지 못했습니다 ($where): 목록이 아닙니다');
  }
  return [
    for (var i = 0; i < value.length; i++) _requireMap(value[i], '$where[$i]'),
  ];
}

/// 사람이 읽는 요약. 기계는 `--json` 을 쓴다.
///
/// 문자열 한 글자도 바꾸면 안 된다 — 스크립트가 이 출력을 파싱한다.
/// 타입 구멍만 막는다.
/// 랑데부 상태 한 줄. `status` 와 `relay` 명령이 같은 문장을 쓴다 —
/// 두 곳에서 다르게 말하면 어느 쪽을 믿어야 할지 모른다.
String _relayLine(Map<String, dynamic> relay) => switch (relay['status']) {
  'ready' => '방 코드 ${relay['code']} · 이 길로 ${relay['participants']}명 접속',
  'connecting' => '붙는 중…',
  'retrying' => '끊김 — 다시 붙는 중 (코드는 유지)',
  'denied' => '거절당함 (${relay['deniedReason'] ?? "이유 모름"})',
  _ => '꺼짐',
};

String _human(String cmd, Map<String, dynamic> r) {
  switch (cmd) {
    case 'state':
    case 'status':
      final room = _optionalMap(r['room'], 'room') ?? const <String, dynamic>{};
      final players =
          _optionalMap(r['players'], 'players') ?? const <String, dynamic>{};
      final game = _optionalMap(r['game'], 'game');
      final net =
          _optionalMap(r['network'], 'network') ?? const <String, dynamic>{};
      final list = r['rooms'];
      final b = StringBuffer();
      // 방이 여럿이면 전체를 먼저 보여준다 — 지금 보고 있는 방만 알려주면
      // 다른 방에서 판이 도는 것을 놓친다.
      if (list is List && list.length > 1) {
        for (final x in _mapList(list, 'rooms')) {
          // status/state 의 rooms[].game 은 {id,name,…} 객체다
          // (rooms 명령은 문자열 id — 아래 case 'rooms' 참고).
          final roomGame = _optionalMap(x['game'], 'rooms[].game');
          final name = x['name'] as String;
          b.writeln(
            '${x['token'] == r['selected'] ? "▶" : " "} '
            '${x['token']}  '
            '${name.isEmpty ? "(이름 없음)" : name}'
            '  ${x['connected']}명'
            '${x['open'] == true ? "" : " · 닫힘"}'
            '${x['hasPin'] == true ? " · 🔒" : ""}'
            '${roomGame != null ? " · ${roomGame['name']} 진행중" : ""}',
          );
        }
        b.writeln('');
      }
      b
        ..writeln(
          '방      ${room['open'] == true ? "열림" : "닫힘"}'
          '${room['token'] != null ? "  ${room['token']}" : ""}'
          '${r['live'] == false ? "  (앱 꺼짐)" : ""}',
        )
        ..writeln('주소    ${room['url'] ?? "-"}')
        ..writeln('참가자  ${players['connected']}/${players['total']}명 접속')
        ..writeln(
          '방정책  최대 ${_optionalMap(r['roomPolicy'], 'roomPolicy')?['max'] ?? "?"}개'
          ' · 수명 ${_optionalMap(r['roomPolicy'], 'roomPolicy')?['ttlHours'] ?? "?"}시간'
          '${_optionalMap(r['roomPolicy'], 'roomPolicy')?['full'] == true ? " · 가득 참" : ""}',
        )
        ..writeln(
          '판      ${game == null ? "없음" : "${game['title']} — ${game['status']}"}',
        );
      if (_optionalMap(r['relay'], 'relay') case final relay?
          when relay['status'] != 'off') {
        // 켜짐만 보고 잘 돌고 있다고 판단하면 안 된다 — 코드를 못 받았거나
        // 아무도 그 길로 안 들어와 있을 수 있다.
        b.writeln('랑데부  ${_relayLine(relay)}');
      }
      if (net['tunnelRunning'] == true) b.writeln('인터넷  개방 중');
      if (net['externalDead'] == true) b.writeln('인터넷  저장된 주소가 죽어 있음');
      if (r['staleSeconds'] case final s?) b.writeln('갱신    $s초 전');
      return b.toString().trimRight();

    case 'relay':
      if (r['configured'] != true) {
        return '랑데부 꺼짐 — 서버 주소가 없습니다\n'
            '화면의 [주소 → 밖에 있는 사람 들이기] 에서 정하세요';
      }
      return '랑데부  ${_relayLine(r)}\n서버    ${r['base']}'
          '${r['serverVersion'] != null ? " · 판 ${r['serverVersion']}" : ""}'
          '${r['serverAssets'] != null ? " · 화면 ${r['serverAssets']}" : ""}'
          '${r['url'] != null ? "\n참가자  ${r['url']}" : ""}';

    case 'players':
      final list = _mapList(r['players'], 'players');
      if (list.isEmpty) return '참가자 없음';
      return list
          .map(
            (p) =>
                '${p['connected'] == true ? "●" : "○"} '
                '${p['tag']}  ${p['nickname']}',
          )
          .join('\n');

    case 'games':
      return _mapList(r['games'], 'games')
          .map(
            (g) =>
                '${g['live'] == true ? "▶" : (g['ready'] == true ? " " : "×")} '
                '${g['id'].toString().padRight(8)} ${g['title']} '
                '(${g['minPlayers']}명+)',
          )
          .join('\n');

    case 'files':
      final fl = _mapList(r['files'], 'files');
      if (fl.isEmpty) return '공유된 자료 없음';
      return fl
          .map(
            (f) =>
                '${f['id']}  ${f['name']}  '
                '(${f['owner']} · ${((f['size'] as num) / 1024).round()}KB · ${f['section']})',
          )
          .join('\n');

    case 'room':
      // addresses 가 있을 때만 표로 찍고, 없으면(방 생성·pin 등) JSON 덤프.
      // null 과 "없는 키" 모두 덤프로 가야 해서 `as List?` 와 같은 분기.
      final ad = r['addresses'];
      if (ad != null) {
        return _mapList(ad, 'addresses')
            .map(
              (a) =>
                  '${a['selected'] == true ? "▶" : " "} '
                  '${a['index']}  ${a['ip'].toString().padRight(16)} '
                  '${a['label']} · ${a['interface']}',
            )
            .join('\n');
      }
      return const JsonEncoder.withIndent('  ').convert(r);

    case 'rooms':
      // rooms 명령의 game 은 문자열 id(또는 null) — status 의 객체와 다르다.
      // 그래서 여기선 Map 으로 캐스팅하지 않고 그대로 찍는다.
      return _mapList(r['rooms'], 'rooms')
          .map((x) {
            final name = x['name'] as String;
            return '${x['selected'] == true ? "▶" : " "} '
                '${x['token']}  ${name.isEmpty ? "(이름 없음)" : name}'
                '  ${x['connected']}명'
                '${x['open'] == true ? "" : " · 닫힘"}'
                '${x['hasPin'] == true ? " · 🔒" : ""}'
                '${x['game'] != null ? " · ${x['game']} 진행중" : ""}';
          })
          .join('\n');

    case 'sections':
      return _mapList(r['sections'], 'sections')
          .map(
            (s) =>
                '${s['id'] == r['active'] ? "▶" : " "} '
                '${s['kind'] == 'room' ? '전체' : '${s['gameName']} ${s['round']}판'}'
                '  메시지 ${s['messages']}  자료 ${s['files'] ?? 0}'
                '${s['live'] == true ? "  (진행 중)" : ""}',
          )
          .join('\n');

    default:
      return const JsonEncoder.withIndent('  ').convert(r);
  }
}

const _usage = '''
파티룸 CLI — 호스트 앱을 화면 없이 조종한다.

  partyroom state              마지막 게시 상태 (앱이 꺼져 있어도)
  partyroom status             떠 있는 앱의 지금 상태
  partyroom players            참가자 목록
  partyroom games              종목과 시작 가능 여부
  partyroom sections           대화·자료 칸

  partyroom start <게임id>      판 시작
      ladder  --outcomes 당첨,꽝,꽝
      poll    --question "저녁?" --options 치킨,피자
  partyroom end                진행 중인 판 끝내기
  partyroom marble launch|skip 구슬 출발 / 건너뛰기
  partyroom ladder next|all    사다리 한 줄 / 남은 전부
  partyroom chat <말>           호스트로 한마디
  partyroom kick <태그>         참가자 내보내기

  partyroom capabilities       기계가 읽는 자기소개
  --json                       모든 명령에 붙일 수 있다

exit: 0 성공 · 64 사용법 · 1 실행 실패
''';

class _Usage implements Exception {
  _Usage(this.message);
  final String message;
}

class _Failure implements Exception {
  _Failure(this.message, {this.code = 1});
  final String message;
  final int code;
}
