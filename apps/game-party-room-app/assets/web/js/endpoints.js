// 참가자 SPA 가 서버에 닿는 모든 주소를 만드는 곳.
//
// 예전에는 `ws://`·`/img/…`·`/api/join` 이 화면 코드 곳곳에 문자열로 박혀 있었다.
// 그 중 WebSocket 스킴이 `ws://` 로 고정돼 있어서, 방을 https 터널로 열면
// 브라우저가 혼합 콘텐츠로 소켓만 차단했다 — 페이지·입장은 되는데 화면이 안 바뀌고
// 호스트에는 "참가자 0명" 으로 보이는 증상. 주소 조립을 여기 한 곳으로 모은다.
window.Endpoints = (function () {
  /** 페이지가 https 면 wss, 아니면 ws. */
  function wsScheme() {
    return window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  }

  /** 랑데부를 지나 왔으면 그 방 코드. 같은 망에서 곧장 왔으면 빈 문자열.
   *
   * 이게 붙어 있으면 페이지를 준 것이 호스트가 아니라 랑데부 서버라는 뜻이다.
   * 그러면 소켓과 입장 요청도 랑데부로 가야 한다 — 랑데부는 이 코드로
   * 어느 호스트에게 넘길지 고른다. 방 토큰(`room`)은 그대로 따라간다:
   * 랑데부는 방이 여럿인지 아닌지도 모르고, 호스트가 자기 목록에서 고른다.
   */
  const relayCode = new URLSearchParams(window.location.search).get('c') || '';

  function withCode(url) {
    if (!relayCode) return url;
    return url + (url.indexOf('?') >= 0 ? '&' : '?') +
      'c=' + encodeURIComponent(relayCode);
  }

  /** 지금 랑데부를 지나고 있는가 — 화면이 자료 기능을 감출 때 본다. */
  function viaRelay() {
    return relayCode !== '';
  }

  /** 방 소켓 주소.
   *
   * 세션 토큰은 **주소에 넣지 않는다** — 붙은 뒤 첫 프레임(auth)으로 보낸다.
   * URL 은 브라우저 방문기록·중간 프록시 로그에 남고, 인터넷 개방 시에는
   * Cloudflare 접속 로그에도 남는다. 세션 토큰은 그 사람 자체라, 남는
   * 자리를 줄일 수 있으면 줄인다. 방 토큰은 어차피 QR 에 찍혀 있다.
   */
  function socket(room) {
    return withCode(
      `${wsScheme()}//${window.location.host}/ws?room=${encodeURIComponent(room)}`,
    );
  }

  /** 입장 API. */
  function join() {
    return withCode('/api/join');
  }

  /** 번들 이미지 (역할 카드·씬 일러스트). 이름만 받는다. */
  function image(name) {
    return `/img/${name}`;
  }

  /** 라이어 커스텀 이미지 — 게임마다 바뀌므로 캐시를 피한다. */
  function liarImage(cacheBuster) {
    return `/liar-image?t=${cacheBuster}`;
  }

  /** 공유 자료 내려받기. */
  function fileUrl(id, room) {
    return `/file/${encodeURIComponent(id)}?room=${encodeURIComponent(room)}`;
  }

  /** 공유 자료 올리기. 세션은 x-party-session 헤더로 보낸다(위와 같은 이유).
   *  [section] 은 어느 칸에 넣을지 — 안 주면 서버가 지금 열린 칸에 넣는다. */
  function upload(room, name, section) {
    return `/api/upload?room=${encodeURIComponent(room)}` +
      `&name=${encodeURIComponent(name)}` +
      (section ? `&section=${encodeURIComponent(section)}` : '');
  }

  return { wsScheme, viaRelay, socket, join, image, liarImage, fileUrl, upload };
})();
