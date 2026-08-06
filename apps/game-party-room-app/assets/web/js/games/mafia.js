// 마피아 — 참가자 화면.
//
// 씬 렌더러와 개인 결과 메시지를 이 종목이 직접 등록한다.
// 화면 골격($ · show · esc · send · pickTarget)은 index.html 이 제공한다.
(function () {
  const ROLE_IMG = {
    mafia: 'role_mafia.png',
    spy: 'role_spy.png',
    doctor: 'role_doctor.png',
    police: 'role_police.png',
    soldier: 'role_soldier.png',
    sniper: 'role_sniper.png',
    medium: 'role_medium.png',
    reporter: 'role_reporter.png',
    politician: 'role_politician.png',
    lover: 'role_lover.png',
    citizen: 'role_citizen.png',
  };

  /// 역할별 카드 테두리. 마피아 진영은 각진 프레임, 특수직은 장식 프레임,
  /// 일반 시민은 담백한 프레임 — 뒤집는 순간 진영이 먼저 읽힌다.
  const FRAME = {
    mafia: 'frame_mafia.jpg', spy: 'frame_mafia.jpg',
    citizen: 'frame_citizen.jpg',
    doctor: 'frame_special.jpg', police: 'frame_special.jpg',
    soldier: 'frame_special.jpg', sniper: 'frame_special.jpg',
    medium: 'frame_special.jpg', reporter: 'frame_special.jpg',
    politician: 'frame_special.jpg', lover: 'frame_special.jpg',
  };

  const MAFIA_TEAM = ['mafia', 'spy'];

  /// 카드에 붙는 짧은 꼬리표 — 설명을 다 읽지 않아도 성격을 안다.
  const ABILITY = {
    mafia: '밤 행동', spy: '밤 행동', doctor: '밤 행동', police: '밤 행동',
    sniper: '1회 한정', reporter: '1회 한정', soldier: '자동 발동',
    medium: '밤 행동', politician: '투표 2표', lover: '동반 사망',
  };

  const NIGHT_PROMPT = {
    mafia: '제거할 대상을 선택하세요',
    doctor: '보호할 사람을 선택하세요',
    police: '조사할 사람을 선택하세요',
    spy: '직업을 알아낼 사람을 선택하세요',
    sniper: '저격할 대상을 선택하세요 (단 한 번!)',
    medium: '정체를 확인할 죽은 자를 선택하세요',
    reporter: '취재할 사람을 선택하세요 (단 한 번, 내일 아침 공개)',
  };

  /** 낮 발표 문구에서 어울리는 삽화를 고른다. */
  function dayImage(announcement) {
    const a = announcement || '';
    if (a.includes('희생')) return 'scene_victim.jpg';
    if (a.includes('의사')) return 'scene_doctor_save.jpg';
    if (a.includes('처형')) return 'scene_vote_exec.jpg';
    return 'scene_peaceful.jpg';
  }

  function showResult(text) {
    $('policeResult').classList.remove('hidden');
    $('policeResult').textContent = text;
  }

  GameClient.register('mafia', {
    scenes: {
      mafia_role(msg) {
        $('roleSecret').classList.remove('revealed');
        $('roleImg').src = Endpoints.image(ROLE_IMG[msg.role]);
        $('roleFrame').style.backgroundImage =
          `url(${Endpoints.image(FRAME[msg.role] || 'frame_citizen.jpg')})`;

        const team = MAFIA_TEAM.includes(msg.role) ? '마피아 진영' : '시민 진영';
        const tags = [`<span class="roletag team${
          MAFIA_TEAM.includes(msg.role) ? ' mafia' : ''}">${team}</span>`];
        if (ABILITY[msg.role]) {
          tags.push(`<span class="roletag">${ABILITY[msg.role]}</span>`);
        }
        $('roleTags').innerHTML = tags.join('');
        $('roleName').textContent = msg.roleLabel;
        $('roleName').className =
          'rolename ' +
          (['mafia', 'doctor', 'police', 'citizen'].includes(msg.role)
            ? msg.role
            : 'citizen');
        $('roleDesc').textContent = msg.roleDesc;

        const mates = $('roleMates');
        if (msg.mates && msg.mates.length > 1) {
          mates.classList.remove('hidden');
          mates.textContent = '마피아 팀: ' + msg.mates.join(', ');
        } else if (msg.lovers && msg.lovers.length > 1) {
          mates.classList.remove('hidden');
          mates.textContent = '연인: ' + msg.lovers.join(', ');
        } else {
          mates.classList.add('hidden');
        }
        show('mafia_role');
      },

      mafia_night(msg) {
        $('nightRound').textContent = `${msg.round}일차 밤`;
        $('policeResult').classList.add('hidden');
        if (msg.canAct) {
          $('nightAct').classList.remove('hidden');
          $('nightSleep').classList.add('hidden');
          $('nightPrompt').textContent = NIGHT_PROMPT[msg.role] || '';
          $('nightTargets').innerHTML = msg.targets
            .map((t) => targetBtn(t, 'mafia_night_act'))
            .join('');
          $('nightStatus').textContent = '';
        } else {
          $('nightAct').classList.add('hidden');
          $('nightSleep').classList.remove('hidden');
        }
        show('mafia_night');
      },

      mafia_day(msg) {
        $('dayRound').textContent = `${msg.round}일차 낮`;
        $('dayImg').src = Endpoints.image(dayImage(msg.announcement));
        $('dayAnnounce').innerHTML = esc(msg.announcement).replace(
          /\n/g,
          '<br>',
        );
        $('dayPlayers').innerHTML = msg.players
          .map((p) => `<li>${nameHtml(p)}</li>`)
          .join('');
        // 죽은 사람은 같은 발표를 보되 화면이 다르다.
        show(msg.alive ? 'mafia_day' : 'mafia_dead');
      },

      mafia_vote(msg) {
        $('voteTargets').innerHTML = msg.targets
          .map((t) => targetBtn(t, 'mafia_vote'))
          .join('');
        $('voteStatus').textContent = '고른 뒤 아래 버튼으로 확정하세요';
        show('mafia_vote');
      },

      mafia_dead() {
        show('mafia_dead');
      },

      mafia_end(msg) {
        const mafiaWin = msg.winner === 'mafia';
        $('endImg').src = Endpoints.image(
          mafiaWin ? 'win_mafia.jpg' : 'win_citizen.jpg',
        );
        $('endWinner').textContent = mafiaWin ? '마피아 승리!' : '시민 승리!';
        $('endWinner').style.color = mafiaWin ? 'var(--red)' : 'var(--skyInk)';
        $('endExtra').textContent = msg.extra || '';
        // 덧붙일 말이 없으면 빈 상자만 남는다
        $('endExtra').classList.toggle('hidden', !msg.extra);
        $('endReveal').innerHTML =
          '<tr><td><b>참가자</b></td><td><b>역할</b></td><td></td></tr>' +
          msg.reveal
            .map(
              (r) =>
                `<tr><td>${esc(r.nickname)}<span class="ptag">${esc(r.tag || '')}</span></td>` +
                `<td>${esc(r.role)}</td><td>${r.alive ? '생존' : '사망'}</td></tr>`,
            )
            .join('');
        show('mafia_end');
      },
    },

    messages: {
      mafia_act_ack() {
        $('nightStatus').textContent = '전달했습니다. 다시 골라 바꿀 수 있어요';
      },
      mafia_vote_ack() {
        $('voteStatus').textContent = '지목했습니다. 다시 골라 바꿀 수 있어요';
      },
      mafia_police_result(msg) {
        showResult(
          `${msg.nickname} 님은 ${msg.isMafia ? '마피아입니다!' : '마피아가 아닙니다.'}`,
        );
      },
      mafia_spy_result(msg) {
        showResult(`${msg.nickname} 님의 직업: [${msg.roleLabel}]`);
      },
      mafia_medium_result(msg) {
        showResult(`${msg.nickname} 님의 정체: [${msg.roleLabel}]`);
      },
    },
  });
})();
