// 라이어 게임 — 참가자 화면.
(function () {
  GameClient.register('liar', {
    scenes: {
      liar_word(msg) {
        $('wordSecret').classList.remove('revealed');

        // 사회자가 올린 커스텀 이미지 제시어.
        if (msg.hasImage) {
          $('wordImg').src = Endpoints.liarImage(Date.now());
          $('wordImg').classList.remove('hidden');
        } else {
          $('wordImg').classList.add('hidden');
        }

        $('wordCat').textContent = '카테고리: ' + msg.category;
        if (msg.isLiar) {
          $('wordCard').classList.add('liar');
          $('wordW').textContent = '당신은 라이어!';
          $('liarHint').textContent = '제시어를 모릅니다. 아는 척 버텨서 들키지 마세요!';
        } else {
          $('wordCard').classList.remove('liar');
          $('wordW').textContent = msg.word;
          $('liarHint').textContent = '라이어가 눈치채지 못하게 제시어를 설명하세요';
        }
        show('liar_word');
      },

      liar_vote(msg) {
        $('liarTargets').innerHTML = msg.targets
          .map((t) => targetBtn(t, 'liar_vote'))
          .join('');
        $('liarVoteStatus').textContent = '고른 뒤 아래 버튼으로 확정하세요';
        show('liar_vote');
      },

      liar_result(msg) {
        $('liarImg2').src = Endpoints.image(
          msg.caught ? 'win_caught.jpg' : 'win_liar.jpg',
        );
        $('liarWinner').textContent = msg.caught
          ? '라이어 검거 성공!'
          : '라이어의 승리!';
        $('liarInfo').textContent =
          `라이어는 ${msg.liar} — 제시어: [${msg.category}] ${msg.word}`;
        $('liarVotes').innerHTML = Object.entries(msg.votes)
          .map(([n, c]) => `<li>${esc(n)} — ${c}표</li>`)
          .join('');
        show('liar_result');
      },
    },

    messages: {
      liar_vote_ack() {
        $('liarVoteStatus').textContent = '지목했습니다. 다시 골라 바꿀 수 있어요';
      },
    },
  });
})();
