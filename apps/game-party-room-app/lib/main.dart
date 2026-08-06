import 'dart:async';

import 'package:flutter/material.dart';
import 'dart:ui' show AppExitResponse;

import 'host_controller.dart';
import 'pages/rooms_page.dart';
import 'server/diagnostics.dart';

void main() {
  // 오류를 삼키지 않고 파일로 남긴 뒤 계속 간다 — 파티 도중에 창이 닫히면
  // 그 자리가 끝난다. runZonedGuarded 로 감싸야 비동기 오류까지 들어온다.
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      Diagnostics.instance.install();
      runApp(const PartyRoomApp());
    },
    (error, stack) =>
        Diagnostics.instance.record(error, stack, context: 'zone'),
  );
}

class PartyRoomApp extends StatefulWidget {
  const PartyRoomApp({super.key});

  @override
  State<PartyRoomApp> createState() => _PartyRoomAppState();
}

class _PartyRoomAppState extends State<PartyRoomApp> {
  final ctrl = HostController();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    ctrl.start();
    // 맥에서 앱을 끝낼 때 dispose 는 불리지 않는다 — 종료 요청을 직접 받아
    // 터널(cloudflared)을 접고 나간다. 안 접으면 공개 주소가 살아남는다.
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await ctrl.shutdown();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '파티룸',
      theme: ThemeData.light(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2FB3FF)),
        scaffoldBackgroundColor: const Color(0xFFF4F7FB),
        textTheme: Typography.blackMountainView.apply(
          fontFamily: 'NexonLv2Gothic',
          fontFamilyFallback: ['Apple Color Emoji', 'sans-serif'],
        ),
      ),
      home: RoomsPage(ctrl: ctrl),
    );
  }
}
