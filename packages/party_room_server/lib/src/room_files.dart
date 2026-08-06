import 'dart:io';

import 'room_limits.dart';

/// 방에서 주고받는 파일 하나.
///
/// 실체는 항상 **디스크의 파일**이다 — 호스트가 공유한 것은 원본 경로를,
/// 참가자가 올린 것은 임시 디렉터리에 받아 둔 사본을 가리킨다. 사진·영상이
/// 오가는 채널이라 메모리에 들면 방 하나가 램을 다 먹는다.
class SharedFile {
  SharedFile({
    required this.id,
    required this.name,
    required this.size,
    required this.mime,
    required this.path,
    required this.ownerTag,
    required this.ownerName,
    required this.at,
    required this.deleteOnRemove,
    required this.sectionId,
  });

  final String id;
  final String name;
  final int size;
  final String mime;
  final String path;

  /// 올린 사람. 호스트가 공유했으면 빈 문자열.
  final String ownerTag;
  final String ownerName;
  final DateTime at;

  /// 목록에서 지울 때 디스크 파일도 지울지 — 업로드 사본만 true.
  /// 호스트 원본을 지우면 방을 닫았는데 호스트 문서가 사라진다.
  final bool deleteOnRemove;

  /// 어느 섹션에서 올라온 자료인지 — '전체'(room) 또는 판 섹션 id.
  /// 파티가 끝난 뒤 "마피아 3판 때 찍은 사진" 을 찾는 유일한 실마리다.
  final String sectionId;

  Map<String, dynamic> toWire() => {
    'id': id,
    'section': sectionId,
    'name': name,
    'size': size,
    'mime': mime,
    'owner': ownerName,
    'ownerTag': ownerTag,
    'ts': at.millisecondsSinceEpoch,
  };

  /// 저장용 — [toWire] 와 달리 디스크 경로가 들어간다. 폰으로는 절대 안 간다.
  Map<String, dynamic> toJson() => {
    ...toWire(),
    'path': path,
    'deleteOnRemove': deleteOnRemove,
  };

  static SharedFile fromJson(Map<String, dynamic> j) => SharedFile(
    id: j['id'] as String,
    name: j['name'] as String,
    size: (j['size'] as num).toInt(),
    mime: j['mime'] as String,
    path: j['path'] as String,
    ownerTag: j['ownerTag'] as String? ?? '',
    ownerName: j['owner'] as String? ?? '',
    at: DateTime.fromMillisecondsSinceEpoch((j['ts'] as num).toInt()),
    deleteOnRemove: j['deleteOnRemove'] as bool? ?? false,
    sectionId: j['section'] as String? ?? 'room',
  );
}

/// 확장자 → Content-Type. 브라우저가 미리보기/저장을 제대로 고르게 한다.
String mimeOf(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'mp4' => 'video/mp4',
    'mov' => 'video/quicktime',
    'mp3' => 'audio/mpeg',
    'm4a' => 'audio/mp4',
    'pdf' => 'application/pdf',
    'zip' => 'application/zip',
    'txt' || 'md' => 'text/plain; charset=utf-8',
    _ => 'application/octet-stream',
  };
}

/// 방의 공유 파일 목록.
class RoomFiles {
  RoomFiles({this.limits = const RoomLimits()});

  /// 숫자의 정본은 여기가 아니라 [RoomLimits] 다 — 서버와 참가자 화면이
  /// 같은 값을 봐야 해서 한 곳에 모아 뒀다.
  final RoomLimits limits;

  final List<SharedFile> _files = [];
  Directory? _uploadDir;

  /// 임시 디렉터리를 만드는 중인 작업. `_uploadDir ??= await …` 로 쓰면
  /// 첫 업로드 두 건이 동시에 들어왔을 때 **둘 다** null 을 보고 각자
  /// 디렉터리를 만든다 — 늦게 끝난 것만 `_uploadDir` 에 남아서, 먼저 만든
  /// 디렉터리는 [dispose] 가 못 찾고 임시 폴더에 영영 쌓인다.
  /// Future 를 먼저 담아 두면(대입은 동기다) 둘째는 같은 것을 기다린다.
  Future<Directory>? _uploadDirPending;

  /// 업로드 사본이 사는 임시 디렉터리의 이름표.
  static const _dirPrefix = 'party_room_files_';

  /// 살아 있는 실행이 이 디렉터리를 쓰고 있다는 표시. 안에 PID 를 적는다.
  static const _lockName = '.owner';

  Future<Directory> _ensureUploadDir() =>
      _uploadDirPending ??= _createUploadDir();

  Future<Directory> _createUploadDir() async {
    final dir = await Directory.systemTemp.createTemp(_dirPrefix);
    // 남의 청소로부터 자신을 지킨다 — 아래 [sweepStale] 이 이 PID 를 본다.
    try {
      await File(
        '${dir.path}${Platform.pathSeparator}$_lockName',
      ).writeAsString('$pid', flush: true);
    } catch (_) {
      // 표시를 못 남겨도 업로드 자체는 되게 둔다.
    }
    _uploadDir = dir;
    return dir;
  }

  /// 지난 실행이 남긴 업로드 사본을 지운다. 방을 열기 전에 한 번 부른다.
  ///
  /// [dispose] 는 방을 정상적으로 닫을 때만 돈다 — 앱을 강제 종료하면
  /// 손님들이 올린 사진·영상이 임시 폴더에 그대로 남는다(한 방에 최대
  /// 30개 × 30MB). 화면 어디에도 안 보이는 자리라 아무도 못 지운다.
  /// 앱은 한 번에 하나만 뜨지만(포트가 막아 준다) 이 패키지는 혼자서도
  /// 돌 수 있다 — 테스트든 다른 호스트든 방 서버가 둘일 수 있다. 접두사만
  /// 보고 지우면 **살아 있는 남의 업로드**를 지워서 그쪽 참가자의 다운로드가
  /// 갑자기 404 가 된다. 그래서 주인 PID 가 아직 살아 있으면 건너뛴다.
  static int sweepStale() {
    var removed = 0;
    try {
      for (final e in Directory.systemTemp.listSync()) {
        if (e is! Directory) continue;
        if (!e.path.split(Platform.pathSeparator).last.startsWith(_dirPrefix)) {
          continue;
        }
        if (_ownerAlive(e)) continue;
        try {
          e.deleteSync(recursive: true);
          removed++;
        } catch (_) {
          // 권한·사용 중이면 건너뛴다.
        }
      }
    } catch (_) {}
    return removed;
  }

  /// 표시된 PID 가 아직 도는지. 표시가 없으면(옛 버전이 남긴 것) 죽은 것으로
  /// 보고 지운다 — 원래 하던 청소를 잃지 않기 위해서다.
  static bool _ownerAlive(Directory dir) {
    try {
      final f = File('${dir.path}${Platform.pathSeparator}$_lockName');
      if (!f.existsSync()) return false;
      final owner = int.tryParse(f.readAsStringSync().trim());
      if (owner == null) return false;
      // 내가 지금 쓰고 있는 폴더는 당연히 살아 있다. (시작 시점 청소에서는
      // 내 PID 로 된 폴더가 아직 없으므로 원래 하던 청소를 잃지 않는다.)
      if (owner == pid) return true;
      // 신호 0 은 "있는지만 보기" 다. macOS·리눅스 공통.
      return Process.runSync('/bin/kill', ['-0', '$owner']).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  List<SharedFile> get files => List.unmodifiable(_files);

  /// 이 방의 업로드 사본이 사는 폴더. 아직 아무도 안 올렸으면 null.
  Directory? get uploadDir => _uploadDir;

  List<Map<String, dynamic>> toJson() => [for (final f in _files) f.toJson()];

  /// 저장분에서 목록을 되살린다.
  ///
  /// **디스크에 실제로 남아 있는 것만** 받는다. 업로드 사본은 임시 폴더에
  /// 살고 그 폴더는 재시작 청소([sweepStale])에 사라지므로, 메타데이터만
  /// 살려 두면 자료함에 "누르면 404 나는 항목" 이 줄줄이 남는다. 호스트가
  /// 자기 맥에서 공유한 파일은 제자리에 있으니 그대로 돌아온다.
  void restore(List<dynamic>? raw) {
    if (raw == null) return;
    for (final e in raw) {
      try {
        final f = SharedFile.fromJson((e as Map).cast<String, dynamic>());
        if (!File(f.path).existsSync()) continue;
        _files.add(f);
      } catch (_) {
        // 항목 하나가 깨졌다고 자료함 전체를 잃을 이유는 없다.
      }
    }
  }

  /// 사라진 칸의 자료를 함께 치운다.
  ///
  /// 칸 상한을 넘겨 오래된 판 칸이 밀려나면 그 칸의 파일은 화면 어디에서도
  /// 못 보게 된다. 그런데 목록에는 남아 방 용량을 계속 먹었다 — 아무도 못
  /// 여는 파일 때문에 새 업로드가 거절되는 상태가 된다.
  ///
  /// 목록에서 빼는 것은 그 자리에서(쿼터가 곧바로 정확해진다), 디스크 삭제는
  /// 뒤에서 한다 — 칸이 밀려나는 순간은 판을 새로 시작하는 순간이라 기다릴
  /// 이유가 없다.
  int dropSection(String sectionId) {
    final orphans = _files.where((f) => f.sectionId == sectionId).toList();
    _files.removeWhere((f) => f.sectionId == sectionId);
    for (final f in orphans) {
      if (!f.deleteOnRemove) continue;
      File(f.path).delete().catchError((_) => File(f.path));
    }
    return orphans.length;
  }

  SharedFile? byId(String id) {
    for (final f in _files) {
      if (f.id == id) return f;
    }
    return null;
  }

  List<Map<String, dynamic>> toWire() => _files.map((f) => f.toWire()).toList();

  /// 판 하나를 통째로 치운다 — 결과 화면의 [이 판 자료 지우기].
  Future<int> removeSection(String sectionId) async {
    var n = 0;
    for (final f in inSection(sectionId)) {
      if (await remove(f.id)) n++;
    }
    return n;
  }

  List<SharedFile> inSection(String sectionId) =>
      _files.where((f) => f.sectionId == sectionId).toList();

  bool isSectionFull(String sectionId) =>
      inSection(sectionId).length >= limits.filesPerSection;

  int get totalBytes =>
      _files.fold<int>(0, (sum, f) => sum + f.size) +
      _pending.fold<int>(0, (sum, r) => sum + r.bytes);

  /// 아직 디스크에 다 안 쓰였지만 **몫은 이미 잡은** 업로드.
  ///
  /// 쿼터 검사와 목록 등록 사이에는 파일을 쓰는 `await` 가 있다. 예전에는 그
  /// 틈에 들어온 두 번째 업로드가 똑같이 빈 몫을 보고 통과해서, 1개 제한에
  /// 2개가 들어앉았다. 검사하는 순간 자리를 잡아 두면 그 틈이 없어진다.
  final List<({String sectionId, String ownerTag, int bytes})> _pending = [];

  int _countIn(String sectionId, {String? ownerTag}) =>
      inSection(
        sectionId,
      ).where((f) => ownerTag == null || f.ownerTag == ownerTag).length +
      _pending
          .where(
            (r) =>
                r.sectionId == sectionId &&
                (ownerTag == null || r.ownerTag == ownerTag),
          )
          .length;

  /// 더 올릴 수 있는지 — 못 올리면 사람이 읽을 이유를 준다.
  /// 호스트(빈 태그)는 자기 맥의 자료를 나눠 주는 쪽이라 개인 몫을 안 따진다.
  String? quotaRefusal(String sectionId, String ownerTag, int bytes) {
    if (totalBytes + bytes > limits.totalBytes) {
      return '방 전체 용량(${limits.totalBytes ~/ (1024 * 1024)}MB)이 찼습니다';
    }
    if (_countIn(sectionId) >= limits.filesPerSection) {
      return '이 칸에 올릴 수 있는 개수(${limits.filesPerSection}개)를 넘었습니다';
    }
    if (ownerTag.isEmpty) return null;
    if (_countIn(sectionId, ownerTag: ownerTag) >= limits.filesPerOwner) {
      return '한 칸에 한 사람이 올릴 수 있는 개수(${limits.filesPerOwner}개)를 넘었습니다';
    }
    final used =
        inSection(sectionId)
            .where((f) => f.ownerTag == ownerTag)
            .fold<int>(0, (sum, f) => sum + f.size) +
        _pending
            .where((r) => r.sectionId == sectionId && r.ownerTag == ownerTag)
            .fold<int>(0, (sum, r) => sum + r.bytes);
    if (used + bytes > limits.bytesPerOwner) {
      return '한 칸에 한 사람이 올릴 수 있는 용량'
          '(${limits.bytesPerOwner ~/ (1024 * 1024)}MB)을 넘었습니다';
    }
    return null;
  }

  /// 호스트가 디스크의 파일을 공유 목록에 올린다.
  Future<SharedFile?> shareHostFile({
    required String id,
    required String path,
    required String sectionId,
  }) async {
    final file = File(path);
    if (!await file.exists()) return null;
    // 호스트 자료도 방 전체 용량은 함께 쓴다 — 예전에는 개수만 봐서, 호스트가
    // 큰 영상을 얹으면 방 용량이 소리 없이 넘어가고 그 뒤로 손님들의 업로드가
    // 이유 없이 거절됐다.
    if (totalBytes + await file.length() > limits.totalBytes) return null;
    final name = path.split(Platform.pathSeparator).last;
    // 표시 이름('호스트')은 화면이 붙인다 — 빈 태그가 곧 호스트라는 뜻이다.
    final shared = SharedFile(
      id: id,
      name: name,
      size: await file.length(),
      mime: mimeOf(name),
      path: path,
      ownerTag: '',
      ownerName: '',
      at: DateTime.now(),
      deleteOnRemove: false,
      sectionId: sectionId,
    );
    _files.add(shared);
    return shared;
  }

  /// 참가자가 올린 바이트를 임시 파일로 받아 목록에 올린다.
  ///
  /// 쿼터는 **여기가 최종 판정**이다. 부르는 쪽도 본문을 다 받기 전에 미리
  /// 한 번 물어보지만(30MB 를 받아 놓고 거절하지 않으려고), 그 사이에 남이
  /// 끼어들 수 있으므로 자리를 잡는 것은 이 안에서 한다.
  Future<({SharedFile? file, String? refusal})> saveUpload({
    required String id,
    required String name,
    required List<int> bytes,
    required String ownerTag,
    required String ownerName,
    required String sectionId,
  }) async {
    // 검사 → 예약까지 await 가 없다. 그래서 틈이 없다.
    final refusal = quotaRefusal(sectionId, ownerTag, bytes.length);
    if (refusal != null) return (file: null, refusal: refusal);
    final slot = (
      sectionId: sectionId,
      ownerTag: ownerTag,
      bytes: bytes.length,
    );
    _pending.add(slot);

    try {
      final dir = await _ensureUploadDir();
      final path = '${dir.path}${Platform.pathSeparator}$id';
      await File(path).writeAsBytes(bytes, flush: true);
      final shared = SharedFile(
        id: id,
        name: name,
        size: bytes.length,
        mime: mimeOf(name),
        path: path,
        ownerTag: ownerTag,
        ownerName: ownerName,
        at: DateTime.now(),
        deleteOnRemove: true,
        sectionId: sectionId,
      );
      _files.add(shared);
      return (file: shared, refusal: null);
    } finally {
      // 성공하면 _files 가 자리를 이어받고, 실패하면 그냥 놓아 준다.
      _pending.remove(slot);
    }
  }

  Future<bool> remove(String id) async {
    final f = byId(id);
    if (f == null) return false;
    _files.remove(f);
    if (f.deleteOnRemove) {
      try {
        await File(f.path).delete();
      } catch (_) {
        // 이미 없어도 목록 정리는 유효하다.
      }
    }
    return true;
  }

  /// 방을 닫을 때 업로드 사본을 청소한다.
  Future<void> dispose() async {
    for (final f in _files.where((f) => f.deleteOnRemove)) {
      try {
        await File(f.path).delete();
      } catch (_) {}
    }
    _files.clear();
    try {
      await _uploadDir?.delete(recursive: true);
    } catch (_) {}
    _uploadDir = null;
  }
}
