import 'package:flutter_test/flutter_test.dart';
import 'package:game_party_room_app/main.dart';

void main() {
  testWidgets('host screen shows title', (tester) async {
    await tester.pumpWidget(const PartyRoomApp());
    expect(find.textContaining('파티룸'), findsWidgets);
  });
}
