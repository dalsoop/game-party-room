// 단톡 + 자료함 — 참가자 화면의 방 채널.
//
// 채널은 하나가 아니라 **섹션**이다. '전체' 는 방이 열려 있는 내내 살고,
// 게임을 시작할 때마다 그 판의 칸이 열린다. 판이 끝나도 칸은 남아서
// "마피아 3판 때 뭐라고 했더라 / 그때 찍은 사진" 을 나중에 펼쳐 볼 수 있다.
//
// 게임 모듈이 아니다: 로비에서든 게임 중이든 산다. 서버가 보내는
// sections / chat_msg / chat_history / files 를 받고, 보내기는 방 소켓의 send().
window.RoomChat = (function () {
  /** 섹션 id → 메시지 배열. */
  let bySection = {};
  /** 서버가 내려 주는 한계값. 여기 없는 숫자를 화면이 지어내지 않는다 —
   *  예전에는 30MB·200개가 서버와 여기 양쪽에 박혀 있어서 한쪽만 고치면
   *  다른 쪽이 조용히 거짓말을 했다. */
  let limits = {};
  let sections = [];
  let current = 'room';
  let files = [];
  /** 섹션별 안 읽은 수 — 다른 칸에서 온 말도 배지에 잡힌다. */
  let unread = {};
  let open = false;
  let tab = 'chat';

  const $ = (id) => document.getElementById(id);

  const mb = (n) => Math.round(n / 1024 / 1024);

  /** 받은 한계값을 화면에 반영한다 — 입력 길이·안내 문구가 서버와 어긋나지 않게. */
  function applyLimits() {
    const input = $('chatInput');
    if (input && limits.chatTextLength) {
      input.maxLength = limits.chatTextLength;
      input.placeholder = `메시지 (${limits.chatTextLength}자)`;
    }
    const status = $('fileStatus');
    if (status && limits.uploadBytes) {
      status.textContent =
        `사진·영상·문서를 이 칸에 올립니다 (${mb(limits.uploadBytes)}MB 이하)`;
    }
    renderFiles();
  }

  /** 이 사람이 자료를 주고받을 수 있는가.
   *
   * 랑데부(다른 망)를 지나 왔으면 못 한다 — 한 사람 30MB 를 남의 서버로
   * 나르지 않는다. 서버가 `limits.canFiles` 로 알려 준다. 값이 안 오는
   * 옛 서버면 되는 것으로 본다(그 서버에는 랑데부가 아예 없다).
   */
  function canFiles() {
    return limits.canFiles !== false;
  }

  function fmtSize(n) {
    if (n < 1024) return `${n}B`;
    if (n < 1024 * 1024) return `${(n / 1024).toFixed(0)}KB`;
    return `${(n / 1024 / 1024).toFixed(1)}MB`;
  }

  function totalUnread() {
    return Object.values(unread).reduce((a, b) => a + b, 0);
  }

  function sectionOf(id) {
    return sections.find((s) => s.id === id);
  }

  /** 칸 이름은 **화면이 붙인다** — 서버는 kind·gameName·round 라는 사실만 준다. */
  function labelOf(s) {
    if (!s) return '';
    if (s.kind === 'room') return '전체';
    return `${s.gameName || '게임'} ${s.round || 1}판`;
  }

  /** 말한 사람 이름. 호스트·사회자는 역할이라 여기서 이름을 붙인다. */
  function speakerName(m) {
    if (m.speaker === 'host') return '호스트';
    if (m.speaker === 'mc') return '사회자';
    return m.nickname || '';
  }

  /** 지금 칸이 쓰기 가능한가 — 끝난 판에는 말을 못 건다. */
  function writable() {
    const s = sectionOf(current);
    return !s || s.kind === 'room' || s.live;
  }

  function renderTabs() {
    const bar = $('chatSections');
    if (!bar) return;
    // 최근 판이 오른쪽 끝에 오고, 새 판이 열리면 그리로 스크롤된다.
    bar.innerHTML = sections
      .map((s) => {
        const n = unread[s.id] || 0;
        const cls = [
          'sectab',
          s.id === current ? 'sel' : '',
          s.kind === 'game' && !s.live ? 'done' : '',
        ]
          .filter(Boolean)
          .join(' ');
        return `<button class="${cls}" onclick="RoomChat.setSection('${esc(s.id)}')">
          ${esc(labelOf(s))}${n ? `<span class="secbadge">${n > 99 ? '99+' : n}</span>` : ''}
        </button>`;
      })
      .join('');
    const sel = bar.querySelector('.sectab.sel');
    if (sel) sel.scrollIntoView({ inline: 'nearest', block: 'nearest' });
  }

  function renderLog() {
    const log = $('chatLog');
    const msgs = bySection[current] || [];
    log.innerHTML = msgs.length
      ? msgs
          .map((m) => {
            const staff = m.speaker === 'host' || m.speaker === 'mc';
            const mine = !staff && window.MYTAG && m.tag === window.MYTAG;
            // 사회자와 호스트를 갈라 그린다 — LLM 이 지어낸 말이 호스트가 한
            // 말로 읽히면 안 된다.
            const cls = staff ? m.speaker : mine ? 'mine' : '';
            const who = staff
              ? esc(speakerName(m))
              : `${esc(m.nickname)} <span class="ptag">${esc(m.tag)}</span>`;
            return `<div class="cmsg ${cls}">
              <div class="cwho">${who}</div>
              <div class="cbody">${esc(m.text)}</div>
            </div>`;
          })
          .join('')
      : `<div class="cempty">${
          sectionOf(current) && sectionOf(current).kind === 'game'
            ? '이 판의 대화가 여기 남습니다'
            : '여기서 나눈 이야기가 방 전체에 보입니다'
        }</div>`;
    log.scrollTop = log.scrollHeight;

    // 끝난 판은 읽기 전용 — 입력칸을 잠가서 "왜 안 보내지" 를 없앤다.
    const input = $('chatInput');
    const send = $('chatSend');
    const ok = writable();
    if (input) {
      input.disabled = !ok;
      // 쓸 수 있을 때의 문구는 한계값이 정한다(applyLimits) — 여기서 덮으면
      // "300자" 같은 서버가 준 사실이 사라진다.
      // 못 쓰는 이유만 말하고 끝내면 어디로 가야 할지 모른다.
      input.placeholder = ok
        ? (limits.chatTextLength ? `메시지 (${limits.chatTextLength}자)` : '메시지')
        : '끝난 판입니다 — [전체]에서 이야기하세요';
    }
    if (send) send.disabled = !ok;
  }

  function renderFiles() {
    const mine = files.filter((f) => f.section === current);
    $('fileList').innerHTML = mine.length
      ? mine
          .map(
            (f) => `<li>
              <span class="name">${esc(f.name)}</span>
              <span class="fmeta">${esc(f.owner || '호스트')} · ${fmtSize(f.size)}</span>
              ${canFiles()
                ? `<a class="fdl" href="${Endpoints.fileUrl(f.id, ROOM)}" download>${Icon.svg('download', 17)}</a>`
                : ''}
            </li>`,
          )
          .join('')
      : '<li class="fempty">이 칸에 올라온 자료가 없습니다</li>';
    const add = $('fileAddRow');
    if (add) add.classList.toggle('hidden', !writable() || !canFiles());
    // 왜 자리가 없는지 말해 준다. 아무 설명 없이 사라지면 "내 폰만 안 되나?"
    // 가 된다 — 실제로는 이 사람만 다른 망에 있는 것이다.
    const note = $('fileRelayNote');
    if (note) note.classList.toggle('hidden', canFiles());
  }

  function bumpBadge() {
    const badge = $('chatBadge');
    const n = totalUnread();
    if (n <= 0) {
      badge.classList.add('hidden');
      return;
    }
    badge.classList.remove('hidden');
    badge.textContent = n > 99 ? '99+' : String(n);
  }

  /** 지금 보고 있는 칸은 읽은 것으로 친다. */
  function clearUnread() {
    unread[current] = 0;
    bumpBadge();
    renderTabs();
  }

  /** 방 채널 메시지면 처리하고 true. 아니면 false — 게임 라우터가 이어받는다. */
  function onMessage(msg) {
    switch (msg.type) {
      case 'limits':
        limits = msg;
        applyLimits();
        return true;
      case 'sections': {
        sections = msg.sections || [];
        for (const s of sections) {
          if (!bySection[s.id]) bySection[s.id] = [];
        }
        // 새 판이 열리면 그 칸으로 따라간다 — 게임 중 대화는 그 판의 것이다.
        const live = sections.find((s) => s.kind === 'game' && s.live);
        const want = msg.active || (live ? live.id : null);
        if (want && want !== current) {
          current = want;
          unread[current] = 0;
        }
        // 사라진 칸(오래된 판)을 보고 있었다면 전체로 돌아온다.
        if (!sectionOf(current)) current = 'room';
        renderTabs();
        renderLog();
        renderFiles();
        bumpBadge();
        return true;
      }
      case 'chat_msg': {
        const id = msg.section || 'room';
        if (!bySection[id]) bySection[id] = [];
        bySection[id].push(msg);
        const cap = limits.messagesPerSection || 200;
        while (bySection[id].length > cap) bySection[id].shift();
        if (id === current) renderLog();
        if (id !== current || !open || tab !== 'chat') {
          unread[id] = (unread[id] || 0) + 1;
          bumpBadge();
          renderTabs();
        }
        return true;
      }
      case 'chat_history':
        bySection[msg.section || 'room'] = msg.items || [];
        renderLog();
        return true;
      case 'files':
        files = msg.files || [];
        renderFiles();
        return true;
      default:
        return false;
    }
  }

  function setSection(id) {
    if (!sectionOf(id)) return;
    current = id;
    clearUnread();
    renderLog();
    renderFiles();
  }

  function toggle() {
    open = !open;
    $('chatPanel').classList.toggle('open', open);
    if (open && tab === 'chat') {
      clearUnread();
      $('chatLog').scrollTop = $('chatLog').scrollHeight;
    }
  }

  function setTab(next) {
    tab = next;
    $('tabChat').classList.toggle('sel', next === 'chat');
    $('tabFiles').classList.toggle('sel', next === 'files');
    $('chatView').classList.toggle('hidden', next !== 'chat');
    $('filesView').classList.toggle('hidden', next !== 'files');
    if (next === 'chat') clearUnread();
  }

  function sendChat() {
    const input = $('chatInput');
    const text = input.value.trim();
    if (!text || !writable()) return;
    send({ type: 'chat', text, section: current });
    input.value = '';
  }

  async function upload(input) {
    const file = input.files && input.files[0];
    input.value = '';
    if (!file) return;
    const status = $('fileStatus');
    const cap = limits.uploadBytes;
    if (cap && file.size > cap) {
      status.textContent = `${mb(cap)}MB 이하만 올릴 수 있어요`;
      return;
    }
    status.textContent = `올리는 중… ${file.name}`;
    try {
      const res = await fetch(Endpoints.upload(ROOM, file.name, current), {
        method: 'POST',
        headers: { 'x-party-session': SESSION },
        body: file,
      });
      const d = await res.json();
      // 몫을 넘긴 경우엔 서버가 사람이 읽을 이유를 준다.
      status.textContent = d.ok
        ? '올렸습니다'
        : `실패: ${d.message || d.error}`;
    } catch (_) {
      status.textContent = '실패 — 연결을 확인하세요';
    }
  }

  return { onMessage, toggle, setTab, setSection, sendChat, upload, labelOf };
})();
