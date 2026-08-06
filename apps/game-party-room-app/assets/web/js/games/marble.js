// 구슬 룰렛 — 참가자 화면.
//
// 이 종목은 폰에서 할 일이 없다. 큰 화면이 본체고, 폰은 "내 구슬이 어느 것인지"
// 를 알려주는 표식일 뿐이다. 그래서 화면이 둘밖에 없고 버튼이 하나도 없다.
(function () {
  /** 내 구슬을 큰 화면에서 바로 찾을 수 있게 색과 번호를 크게 세운다. */
  function paintMarble(el, color, index) {
    el.style.background = color;
    el.textContent = index + 1;
  }

  GameClient.register('marble', {
    scenes: {
      marble_ready(msg) {
        $('marbleBall').classList.remove('rolling');
        paintMarble($('marbleBall'), msg.color, msg.index);
        $('marbleWho').textContent = msg.nickname;
        $('marbleTotal').textContent = `${msg.total}개 중 ${msg.index + 1}번`;
        $('marbleGoal').textContent =
          msg.goal === 'last' ? '꼴찌가 당첨입니다' : '1등이 당첨입니다';
        $('marbleHint').textContent = '호스트 화면을 보세요';
        show('marble_ready');
      },

      marble_result(msg) {
        const w = msg.winner;
        paintMarble($('marbleWinBall'), w.color, w.index);
        $('marbleWinName').textContent = w.nickname;
        $('marbleWinWhy').textContent =
          msg.goal === 'last'
            ? `꼴찌 (${w.rank}위) — 당첨`
            : `1등 (${w.rank}위) — 당첨`;

        $('marbleRanks').innerHTML = msg.ranking
          .map(
            (r) => `<li>
              <span class="rankno">${r.rank}</span>
              <span class="marbledot" style="background:${esc(r.color)}"></span>
              <span class="name">${esc(r.nickname)}</span>
              <span class="ptag">${esc(r.tag || '')}</span>
            </li>`,
          )
          .join('');
        // 시드를 적어 둔다 — 뽑기로 쓰는 이상 "어떻게 나온 결과냐" 에
        // 답할 수 있어야 하고, 같은 시드는 같은 순위를 만든다.
        $('marbleSeed').textContent = `추첨 번호 ${msg.seed}`;
        show('marble_result');
      },
    },

    messages: {
      marble_start() {
        $('marbleHint').textContent = '출발! 화면을 보세요';
        $('marbleBall').classList.add('rolling');
      },
    },
  });
})();
