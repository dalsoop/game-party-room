import 'package:shelf/shelf.dart';

import 'asset_source.dart';

/// 참가자 SPA·폰트·이미지·스크립트 서빙.
///
/// 방 상태와 무관한 순수 정적 서빙이라 방 서버에서 떼어냈고, 자산을 어디서 읽을지는
/// [AssetSource] 로 주입받는다 — 이 덕분에 같은 코드가 호스트 앱(앱 번들)에서도,
/// 헤드리스 서버(파일시스템)에서도 돈다.
///
/// 경로는 그대로 쓰지 않는다. 이름은 화이트리스트로 검사한다.
class WebAssets {
  const WebAssets(this.assets);

  final AssetSource assets;

  /// 이 요청이 자산이면 응답을, 아니면 null(방 서버가 이어받는다).
  Future<Response?> serve(String path) async {
    if (path.isEmpty || path == 'index.html') {
      final html = await assets.loadString('assets/web/index.html');
      if (html == null) return Response.notFound('no index');
      return Response.ok(
        html,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    }

    // 참가자 SPA 스크립트. 종목 스크립트는 js/games/ 아래 한 단계까지만.
    if (path.startsWith('js/')) {
      final name = path.substring(3);
      if (!RegExp(r'^(games/)?[a-z0-9_-]+\.js$').hasMatch(name)) {
        return Response.notFound('bad asset');
      }
      final js = await assets.loadString('assets/web/js/$name');
      if (js == null) return Response.notFound('no asset');
      return Response.ok(
        js,
        headers: {
          'content-type': 'application/javascript; charset=utf-8',
          // 게임 중 고치는 일이 잦다 — 새로고침하면 항상 최신을 받아야 한다.
          'cache-control': 'no-store',
        },
      );
    }

    if (path == 'fonts/nexon.ttf') {
      final data = await assets.loadBytes(
        'assets/fonts/NEXONLv2Gothic-Regular.ttf',
      );
      if (data == null) return Response.notFound('no font');
      return Response.ok(
        data,
        headers: {'content-type': 'font/ttf', 'cache-control': 'max-age=86400'},
      );
    }

    if (path.startsWith('img/')) {
      final name = path.substring(4);
      // 화이트리스트 — 경로 탈출 원천 차단.
      if (!RegExp(r'^[a-z0-9_]+\.(jpg|png)$').hasMatch(name)) {
        return Response.notFound('bad asset');
      }
      final data = await assets.loadBytes('assets/web/img/$name');
      if (data == null) return Response.notFound('no asset');
      final ct = name.endsWith('.png') ? 'image/png' : 'image/jpeg';
      return Response.ok(
        data,
        headers: {
          'content-type': ct,
          // 파일 이름에 판번호가 없다 — 그림을 바꿔도 이름은 그대로다.
          // max-age 로 두면 지난 파티에 접속했던 폰이 옛 그림을 계속 쓴다.
          // 페이지를 열 때마다 물어보게 하고, 한 판 도는 동안은 브라우저가
          // 메모리에 들고 있으므로 화면마다 다시 받지는 않는다.
          'cache-control': 'no-cache',
        },
      );
    }

    return null;
  }
}
