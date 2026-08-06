// 익명 투표 — 참가자 화면.
(function () {
  GameClient.register('poll', {
    scenes: {
      poll(msg) {
        $('pollQ').textContent = msg.question;
        $('pollOpts').innerHTML = msg.options
          .map((o, i) => choiceBtn(o, i, 'poll_vote'))
          .join('');
        $('pollStatus').textContent = '선택지를 고른 뒤 아래 버튼으로 확정하세요';
        show('poll');
      },

      pollresult(msg) {
        renderPollResult(msg);
        show('pollresult');
      },
    },

    messages: {
      poll_ack(msg) {
        markVote('#pollOpts', msg.option);
        $('pollStatus').textContent = '투표했습니다. 다시 골라 바꿀 수 있어요';
      },
      poll_result(msg) {
        renderPollResult(msg);
        show('pollresult');
      },
    },
  });

  /** 결과 막대 그래프. */
  function renderPollResult(msg) {
    $('resultQ').textContent = msg.question;
    const max = Math.max(...msg.counts, 1);
    $('resultBars').innerHTML = msg.options
      .map(
        (o, i) => `
    <div>${esc(o)} — <b>${msg.counts[i]}표</b></div>
    <div class="bar"><div style="width:${(msg.counts[i] / max) * 100}%"></div></div>`,
      )
      .join('');
    $('resultTotal').textContent = `총 ${msg.total}명 투표`;
  }
})();
