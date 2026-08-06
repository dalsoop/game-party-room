/// 참가자 색 팔레트 — 관전형 종목(구슬 룰렛·사다리타기)의 공용 정본.
///
/// 참가자 폰과 호스트 큰 화면이 같은 표를 봐야 "내 색" 을 찾을 수 있어서
/// 서버가 들고 있다. 20색 — 방 정원과 같다.
const List<String> partyPalette = [
  '#FF4757',
  '#2FB3FF',
  '#2ED573',
  '#FFA502',
  '#A55EEA',
  '#00D2D3',
  '#FF6B81',
  '#1E90FF',
  '#F6B93B',
  '#7BED9F',
  '#EE5A24',
  '#5F27CD',
  '#01A3A4',
  '#FF9FF3',
  '#54A0FF',
  '#C8D6E5',
  '#FD79A8',
  '#00B894',
  '#E17055',
  '#6C5CE7',
];

String partyColorOf(int index) => partyPalette[index % partyPalette.length];
