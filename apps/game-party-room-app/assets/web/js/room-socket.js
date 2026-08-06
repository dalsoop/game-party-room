// 방 서버와의 연결 수명주기 — 접속·자동 재접속·전송.
//
// 화면 코드(index.html)는 "무슨 메시지가 왔나" 만 신경 쓰고,
// "어떻게 붙나" 는 여기가 맡는다.
window.RoomSocket = (function () {
  function create(options) {
    const { room, session, onMessage, onStatus } = options;
    const retryDelayMs = options.retryDelayMs || 1500;

    let ws = null;
    let closedByUs = false;
    let retryTimer = null;

    function status(text) {
      if (onStatus) onStatus(text);
    }

    function connect() {
      // 이전 소켓이 남아 있으면 정리한다 — 겹치면 서버 쪽에서 같은 세션에
      // 소켓이 둘이 되어 재접속 처리가 꼬인다.
      if (ws && ws.readyState <= 1) {
        try {
          ws.close();
        } catch (_) {
          /* 이미 닫힘 */
        }
      }

      ws = new WebSocket(window.Endpoints.socket(room));

      // 세션은 주소가 아니라 첫 프레임으로 보낸다. 서버는 이걸 받기 전까지
      // 이 소켓이 누구인지 모르고, 10초 안에 안 오면 끊는다.
      ws.onopen = () => {
        status('');
        ws.send(JSON.stringify({ type: 'auth', session }));
      };
      ws.onmessage = (ev) => {
        let msg;
        try {
          msg = JSON.parse(ev.data);
        } catch (_) {
          return; // 서버가 보낼 리 없지만, 깨진 프레임에 화면이 죽지 않게
        }
        // 서버가 세션을 못 알아봤다 — 방이 새로 열렸거나(지난 파티 정리)
        // 강퇴됐다. 계속 재접속해 봐야 같은 결과라 다시 입장시킨다.
        if (msg.type === 'auth_failed') {
          closedByUs = true;
          if (options.onAuthFailed) options.onAuthFailed();
          return;
        }
        if (msg.type === 'auth_required') return; // 이미 보냈다
        onMessage(msg);
      };
      ws.onclose = () => {
        if (closedByUs) return;
        status('연결 끊김 — 재접속 중…');
        clearTimeout(retryTimer);
        retryTimer = setTimeout(connect, retryDelayMs);
      };
      // onerror 뒤에는 onclose 가 따라오므로 재시도는 거기서만 건다.
      ws.onerror = () => status('연결 오류 — 재접속 중…');
    }

    function send(obj) {
      if (ws && ws.readyState === 1) {
        ws.send(JSON.stringify(obj));
        return true;
      }
      return false;
    }

    /** 강퇴 등 더 이상 재접속하면 안 될 때. */
    function stop() {
      closedByUs = true;
      clearTimeout(retryTimer);
      if (ws) {
        try {
          ws.close();
        } catch (_) {
          /* 이미 닫힘 */
        }
      }
    }

    return { connect, send, stop };
  }

  return { create };
})();
