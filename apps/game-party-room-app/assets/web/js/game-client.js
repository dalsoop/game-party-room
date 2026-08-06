// 참가자 쪽 게임 레지스트리.
//
// 예전에는 `handle()` 과 `routeScene()` 이라는 거대한 switch 두 개가 모든 종목을
// 알고 있었다. 게임을 하나 넣을 때마다 index.html 이 커졌고, 씬 하나를 빠뜨려도
// 아무 오류 없이 흰 화면만 나왔다(서버는 정상으로 보인다).
//
// 이제 종목이 자기 씬·메시지 처리를 등록한다. 호스트 쪽 GameCatalog 와 같은 구조다.
window.GameClient = (function () {
  /** sceneId → (msg) => void */
  const scenes = {};
  /** messageType → (msg) => void */
  const messages = {};

  /**
   * 종목 등록.
   * @param {string} gameId
   * @param {{scenes?: Object, messages?: Object}} handlers
   */
  function register(gameId, handlers) {
    for (const [k, fn] of Object.entries(handlers.scenes || {})) {
      if (scenes[k]) {
        console.warn(`[GameClient] 씬 중복 등록: ${k} (${gameId})`);
      }
      scenes[k] = fn;
    }
    for (const [k, fn] of Object.entries(handlers.messages || {})) {
      if (messages[k]) {
        console.warn(`[GameClient] 메시지 중복 등록: ${k} (${gameId})`);
      }
      messages[k] = fn;
    }
  }

  /** 서버 메시지 하나를 처리한다. 처리했으면 true. */
  function handle(msg) {
    if (msg.type === 'scene') {
      const fn = scenes[msg.scene];
      if (!fn) {
        // 조용히 넘기면 참가자는 이유 없이 멈춘 화면을 본다.
        console.error(`[GameClient] 모르는 씬: ${msg.scene}`);
        return false;
      }
      fn(msg);
      return true;
    }
    const fn = messages[msg.type];
    if (!fn) return false;
    fn(msg);
    return true;
  }

  /** 등록 현황 — 개발 중 확인용. */
  function registered() {
    return { scenes: Object.keys(scenes), messages: Object.keys(messages) };
  }

  return { register, handle, registered };
})();
