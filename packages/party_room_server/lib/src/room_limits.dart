/// 방이 지키는 한계값 전부.
///
/// 예전에는 이 숫자들이 서버와 참가자 화면에 **각각** 박혀 있었다 — 업로드
/// 30MB 가 `RoomFiles` 와 `chat.js` 양쪽에, 기록 200개가 `RoomChannels` 와
/// `chat.js` 양쪽에, 채팅 300자가 서버와 `index.html` 의 maxlength 양쪽에.
/// 한쪽만 고치면 다른 쪽이 조용히 거짓말을 한다: 상한을 올렸는데 폰이 먼저
/// 거절하거나, 폰은 보내는데 서버가 버린다.
///
/// 이제 값은 여기 한 곳에 있고, 접속할 때 참가자 화면으로 내려간다
/// (`{'type': 'limits'}`). 화면은 이 값을 **받아서** 쓴다.
class RoomLimits {
  const RoomLimits({
    this.players = 20,
    this.chatTextLength = 300,
    this.chatIntervalMs = 300,
    this.messagesPerSection = 200,
    this.sections = 24,
    this.messageBytes = 64 * 1024,
    this.uploadBytes = 30 * 1024 * 1024,
    this.filesPerSection = 30,
    this.filesPerOwner = 6,
    this.bytesPerOwner = 80 * 1024 * 1024,
    this.totalBytes = 1024 * 1024 * 1024,
  });

  /// 방 정원.
  final int players;

  /// 채팅 한 줄의 글자 수. 넘으면 잘라서 남긴다.
  final int chatTextLength;

  /// 같은 사람의 채팅 사이 최소 간격(ms). 더 빨리 보내면 조용히 버린다.
  ///
  /// 이 값이 여기 없고 코드에 박혀 있었다. 그래서 테스트가 "150ms 쯤 기다리면
  /// 되겠지" 하고 우연히 문턱을 넘고 있었고, 기계가 바쁘면 통과하고 한가하면
  /// 실패하는 거꾸로 된 테스트가 됐다.
  final int chatIntervalMs;

  /// 칸 하나가 들고 있는 최근 기록 수. 파티 단톡이지 보관용 메신저가 아니다.
  final int messagesPerSection;

  /// 칸 개수 상한. 오래된 판부터 버린다(전체 칸은 예외).
  final int sections;

  /// 참가자가 보낼 수 있는 메시지 한 건의 크기.
  ///
  /// 오가는 것은 채팅 한 줄과 지목 한 줄뿐이다. 상한이 없으면 참가자 하나가
  /// 거대한 프레임을 계속 밀어 호스트 맥의 램을 채운다.
  final int messageBytes;

  /// 업로드 한 건의 상한. 폰 사진(HEIC 3~8MB)·짧은 영상까지 받는다.
  final int uploadBytes;

  /// 칸 하나가 담는 자료 개수.
  final int filesPerSection;

  /// 한 사람이 **한 칸에서** 차지할 수 있는 몫.
  ///
  /// 칸 상한만 두면 한 명이 그 칸을 다 먹는다 — 악의가 아니라도 사진첩을
  /// 통째로 올리는 사람이 꼭 있다. 판이 바뀌면 몫도 새로 생긴다.
  final int filesPerOwner;
  final int bytesPerOwner;

  /// 방 전체 디스크 상한. 칸이 늘어도 맥의 디스크는 안 늘어난다.
  final int totalBytes;

  /// 참가자 화면이 그대로 읽는 형태. 키 이름이 곧 계약이다.
  Map<String, dynamic> toWire() => {
    'players': players,
    'chatTextLength': chatTextLength,
    'chatIntervalMs': chatIntervalMs,
    'messagesPerSection': messagesPerSection,
    'sections': sections,
    'messageBytes': messageBytes,
    'uploadBytes': uploadBytes,
    'filesPerSection': filesPerSection,
    'filesPerOwner': filesPerOwner,
    'bytesPerOwner': bytesPerOwner,
    'totalBytes': totalBytes,
  };

  RoomLimits copyWith({
    int? players,
    int? chatTextLength,
    int? chatIntervalMs,
    int? messagesPerSection,
    int? sections,
    int? messageBytes,
    int? uploadBytes,
    int? filesPerSection,
    int? filesPerOwner,
    int? bytesPerOwner,
    int? totalBytes,
  }) => RoomLimits(
    players: players ?? this.players,
    chatTextLength: chatTextLength ?? this.chatTextLength,
    chatIntervalMs: chatIntervalMs ?? this.chatIntervalMs,
    messagesPerSection: messagesPerSection ?? this.messagesPerSection,
    sections: sections ?? this.sections,
    messageBytes: messageBytes ?? this.messageBytes,
    uploadBytes: uploadBytes ?? this.uploadBytes,
    filesPerSection: filesPerSection ?? this.filesPerSection,
    filesPerOwner: filesPerOwner ?? this.filesPerOwner,
    bytesPerOwner: bytesPerOwner ?? this.bytesPerOwner,
    totalBytes: totalBytes ?? this.totalBytes,
  );
}
