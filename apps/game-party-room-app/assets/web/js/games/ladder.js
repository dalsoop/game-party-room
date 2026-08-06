// 사다리타기 — 참가자 화면.
//
// 구슬 룰렛과 같은 관전형: 폰이 하는 일은 "내 줄이 몇 번인지" 를 보여 주고,
// 큰 화면의 추적이 끝나면 내 결과를 받는 것뿐이다. 버튼이 하나도 없다.
(function () {
  GameClient.register('ladder', {
    scenes: {
      ladder_ready(msg) {
        const badge = $('ladderBadge');
        badge.style.background = msg.color;
        badge.textContent = msg.column + 1;
        $('ladderWho').textContent = msg.nickname;
        $('ladderTotal').textContent = `${msg.total}줄 중 ${msg.column + 1}번 줄`;
        $('ladderOutcomes').innerHTML = msg.outcomes
          .map(
            (o) => `<li><span class="name">${esc(o)}</span>${
              o === '꽝' ? '' : '<span class="ptag">걸림</span>'
            }</li>`,
          )
          .join('');
        $('ladderHint').textContent = '호스트 화면에서 사다리를 타는 중…';
        show('ladder_ready');
      },

      ladder_result(msg) {
        const badge = $('ladderResBadge');
        badge.style.background = msg.color;
        badge.textContent = msg.column + 1;
        const out = $('ladderOutcome');
        out.textContent = msg.outcome;
        out.classList.toggle('hit', !!msg.hit);
        $('ladderResHint').textContent = msg.hit
          ? '걸렸습니다! 큰 화면을 보세요'
          : '무사히 지나갔습니다';
        show('ladder_result');
      },

      ladder_end(msg) {
        $('ladderTable').innerHTML =
          '<tr><td><b>참가자</b></td><td><b>결과</b></td></tr>' +
          msg.results
            .map(
              (r) =>
                `<tr><td>${esc(r.nickname)}<span class="ptag">${esc(r.tag || '')}</span></td>` +
                `<td>${r.hit ? '<b>' + esc(r.outcome) + '</b>' : esc(r.outcome)}</td></tr>`,
            )
            .join('');
        $('ladderSeed').textContent = `추첨 번호 ${msg.seed}`;
        show('ladder_end');
      },
    },

    messages: {},
  });
})();
