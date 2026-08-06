// UI 글리프.
//
// 이모지를 쓰지 않는다 — 플랫폼마다 모양·색·크기가 제각각이라 화면 톤이 깨지고,
// 흑백 대비도 통제할 수 없다. 인라인 SVG 는 currentColor 를 따라가고 어디서든 같다.
//
// 삽화(역할 오브젝트·씬)는 생성 이미지를 쓰고, 여기 있는 것은 기능 글리프뿐이다.
window.Icon = (function () {
  const S = (d, extra = '') =>
    `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"
       stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" ${extra}>${d}</svg>`;

  const P = {
    // 진행
    moon: '<path d="M20 14.5A8.5 8.5 0 0 1 9.5 4a8.5 8.5 0 1 0 10.5 10.5Z"/>',
    sun: '<circle cx="12" cy="12" r="4.2"/><path d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.2 5.2l1.4 1.4M17.4 17.4l1.4 1.4M18.8 5.2l-1.4 1.4M6.6 17.4l-1.4 1.4"/>',
    // 상태
    eye: '<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12Z"/><circle cx="12" cy="12" r="3"/>',
    eyeOff: '<path d="M4 4l16 16M10 5.9A7.9 7.9 0 0 1 12 5.7c6 0 9.5 6.3 9.5 6.3a17 17 0 0 1-3.2 3.9M6.4 7.9A16.7 16.7 0 0 0 2.5 12S6 18.3 12 18.3a8.6 8.6 0 0 0 3.4-.7"/>',
    alert: '<path d="M12 4.6 2.8 19.4h18.4Z"/><path d="M12 10v4M12 16.6v.1"/>',
    check: '<path d="M4.5 12.5 9.5 17.5 19.5 6.5"/>',
    skull: '<path d="M12 3.2c-4.3 0-7.2 2.9-7.2 6.8 0 2.3 1 3.7 2 4.6.5.4.7.9.7 1.5v1.4c0 .8.6 1.4 1.4 1.4h6.2c.8 0 1.4-.6 1.4-1.4v-1.4c0-.6.2-1.1.7-1.5 1-.9 2-2.3 2-4.6 0-3.9-2.9-6.8-7.2-6.8Z"/><circle cx="9.3" cy="11" r="1.4"/><circle cx="14.7" cy="11" r="1.4"/>',
    // 사람·방
    users: '<circle cx="9" cy="8.4" r="3.2"/><path d="M2.9 19.2a6.1 6.1 0 0 1 12.2 0"/><path d="M16.4 5.6a3.2 3.2 0 0 1 0 5.7M18 19.2a6 6 0 0 0-1.6-4.1"/>',
    door: '<path d="M14.5 3.2H6.2v17.6h8.3z"/><path d="M14.5 3.2 18 4.6v14.8l-3.5 1.4M11 12v.1"/>',
    qr: '<path d="M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4z"/><path d="M14 14h2.5v2.5H14zM17.5 17.5H20V20h-2.5zM14 20h1M20 14h.01"/>',
    // 조작
    // 톱니는 8방향 이빨로 단순화 — 작은 크기에서 복잡한 형태는 뭉개진다.
    gear: '<circle cx="12" cy="12" r="3.2"/><circle cx="12" cy="12" r="7.4" stroke-dasharray="2.6 2.3"/>',
    refresh: '<path d="M20.5 11.5a8.5 8.5 0 1 1-2.5-6"/><path d="M20.5 4v5.5H15"/>',
    left: '<path d="M14.5 5.5 8 12l6.5 6.5"/>',
    right: '<path d="M9.5 5.5 16 12l-6.5 6.5"/>',
    close: '<path d="M6 6l12 12M18 6 6 18"/>',
    note: '<path d="M5.5 3.8h13v16.4h-13z"/><path d="M8.5 8.5h7M8.5 12h7M8.5 15.5h4"/>',
    chat: '<path d="M4 5h16v11H9l-5 4z"/><path d="M8 9.5h8M8 12.5h5"/>',
    download: '<path d="M12 3.5v10M7.5 9.5 12 14l4.5-4.5"/><path d="M4.5 17.5v3h15v-3"/>',
    upload: '<path d="M12 14V4M7.5 8 12 3.5 16.5 8"/><path d="M4.5 17.5v3h15v-3"/>',
    // 게임 성격
    search: '<circle cx="10.7" cy="10.7" r="6.2"/><path d="M15.2 15.2 20 20"/>',
    ballot: '<path d="M3.5 10.5h17v9.5h-17z"/><path d="M8 10.5V4.5h8v6"/><path d="M10.5 7.5h3"/>',
    masks: '<path d="M3.6 6.5h8.8v6.6a4.4 4.4 0 0 1-8.8 0Z"/><path d="M11.6 6.5h8.8v6.6a4.4 4.4 0 0 1-8.8 0Z"/>',
  };

  function svg(name, size = 18) {
    const d = P[name];
    if (!d) return '';
    return S(d, `width="${size}" height="${size}" style="display:block"`);
  }

  /** 요소 안에 아이콘을 넣는다. */
  function into(el, name, size) {
    if (el) el.innerHTML = svg(name, size);
  }

  return { svg, into, has: (n) => !!P[n] };
})();
