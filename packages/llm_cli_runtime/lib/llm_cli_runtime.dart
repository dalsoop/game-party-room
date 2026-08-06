/// 터미널 LLM CLI 런타임 — 구독 로그인된 claude·codex·grok 를 그대로 부른다.
///
/// API 키를 요구하지 않는 것이 요점이다: 사용자가 이미 터미널에서 쓰고 있는
/// 구독을 앱이 빌려 쓴다. swift-app-mono 의 `LLMRuntimeKit` 과 같은 계약.
library;

export 'src/backends.dart';
export 'src/runtime.dart';
