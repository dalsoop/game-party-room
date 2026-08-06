import 'dart:io';

import 'package:party_room_server/party_room_server.dart';
import 'package:test/test.dart';

/// 지난 실행이 남긴 업로드 사본 치우기.
///
/// 앱을 강제 종료하면 dispose 가 안 돌아 손님들이 올린 사진·영상이 임시
/// 폴더에 그대로 남는다(한 방 최대 30개 × 30MB). 화면 어디에도 안 보이는
/// 자리라 아무도 못 지운다 — 다음 실행이 치운다.
void main() {
  test('남아 있던 업로드 폴더를 지운다', () {
    final stale = Directory.systemTemp.createTempSync('party_room_files_');
    File('${stale.path}/손님사진.heic').writeAsStringSync('x');
    final mine = Directory.systemTemp.createTempSync('someone_else_');
    addTearDown(() {
      if (mine.existsSync()) mine.deleteSync(recursive: true);
      if (stale.existsSync()) stale.deleteSync(recursive: true);
    });

    expect(RoomFiles.sweepStale(), greaterThanOrEqualTo(1));
    expect(stale.existsSync(), isFalse);
    expect(mine.existsSync(), isTrue, reason: '남의 임시 폴더를 지우면 안 된다');
  });

  test('치울 것이 없으면 0', () {
    RoomFiles.sweepStale();
    expect(RoomFiles.sweepStale(), 0);
  });
}
