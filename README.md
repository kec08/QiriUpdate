# Qiri - Apple Watch 음성 AI 어시스턴트

> Apple Watch에서 손 제스처와 음성으로 AI에게 질문하고, 실시간 스트리밍 답변을 받아보세요.

Qiri는 **iOS + watchOS** 듀얼 플랫폼 AI 어시스턴트 앱입니다. Apple Watch의 AssistiveTouch(손 제스처) 기능을 활용하여 손목 위에서 음성으로 질문하면, AI가 실시간으로 답변을 스트리밍해 줍니다.

---

## 주요 기능

### Apple Watch (watchOS)
- **음성 질문 입력** — 탭 한 번으로 음성 인식을 시작하고, 말로 질문
- **실시간 스트리밍 답변** — AI의 사고 과정(Thinking)과 최종 답변을 실시간으로 표시
- **단어별 스트리밍 애니메이션** — 답변이 한 단어씩 자연스럽게 나타나는 UI
- **현재 시각 표시** — 메인 화면에서 한국 시간(Asia/Seoul) 실시간 표시
- **온보딩 가이드** — 처음 사용자를 위한 3단계 온보딩 화면
- **자동 재시도** — 네트워크 오류 시 최대 3회 자동 재시도 (2초 간격)

### iPhone (iOS)
- **Apple 로그인** — Apple ID를 통한 간편 인증
- **이용약관 동의 및 디바이스 등록** — 최초 실행 시 약관 동의 후 자동 등록
- **사용 가이드 제공** — 총 4종의 상세 튜토리얼:
  - AssistiveTouch 활성화 방법 (4단계)
  - AssistiveTouch 제스처 커스텀 설정 (7단계)
  - Qiri 사용법 (4단계)
  - iOS 단축어 연동 설정 (5단계)
- **사용자 프로필** — 이메일 확인 및 로그아웃

### iPhone ↔ Apple Watch 연동
- **WatchConnectivity** 기반 실시간 양방향 통신
- Apple User ID 자동 동기화
- 디바이스 등록 상태 공유
- 백그라운드 동기화 (Application Context) 지원

---

## 동작 흐름

### watchOS 흐름
```
스플래시 → 온보딩(3단계) → 메인(시계) → 음성 질문 → AI 사고 표시 → 답변 확인 → 전체 답변 보기
```

### iOS 흐름
```
스플래시 → Apple 로그인 → 이용약관 동의 → 메인(가이드 허브) → 각종 튜토리얼 / 사용자 프로필
```

---

## 기술 스택

| 분류 | 기술 |
|------|------|
| **UI** | SwiftUI |
| **인증** | AuthenticationServices (Apple Sign-In) |
| **네트워크** | URLSession (SSE 스트리밍), Moya |
| **Watch 연동** | WatchConnectivity (WCSession) |
| **아키텍처** | MVVM, NotificationCenter 기반 이벤트 드리븐 상태 머신 |
| **데이터 저장** | UserDefaults |
| **최소 지원** | iOS 16.0+ / watchOS 9.0+ |

---

## 프로젝트 구조

```
Qiri-main/
├── Qiri/                              # iOS 앱
│   ├── App/
│   │   ├── QiriApp.swift              # 앱 진입점
│   │   └── RootView.swift             # 상태 머신 (splash→login→conditions→main)
│   ├── Feature/
│   │   ├── Login/                     # Apple 로그인
│   │   ├── Splash/                    # 스플래시 화면
│   │   ├── Main/                      # 메인 허브 (가이드 목록)
│   │   ├── Conditions/                # 이용약관 동의
│   │   ├── User/                      # 사용자 프로필
│   │   ├── More/                      # 전체 가이드 목록
│   │   └── Learn/                     # 튜토리얼 가이드
│   │       ├── Assistive/             #   - AssistiveTouch 활성화
│   │       ├── CustomView/            #   - 제스처 커스텀 설정
│   │       ├── QiriGuide/             #   - Qiri 사용법
│   │       └── ShortcutView/          #   - 단축어 연동
│   └── Model/Core/
│       ├── Network/                   # API 통신 (Moya, AuthService)
│       └── Extension/                 # Color, Date 확장
│
├── Qiri Watch App/                    # watchOS 앱
│   ├── App/
│   │   ├── QiriApp.swift              # Watch 앱 진입점
│   │   └── RootView.swift             # 상태 머신 (splash→onboarding→main→질문→답변)
│   ├── Feature/
│   │   ├── Splash/                    # 스플래시
│   │   ├── Onboarding/                # 온보딩 (3단계)
│   │   ├── Main/                      # 메인 (시계 + 질문 시작)
│   │   ├── Question/                  # 음성 질문 입력
│   │   ├── Thinking/                  # AI 사고 과정 표시
│   │   └── Answer/                    # 답변 표시 + 전체 답변
│   └── Model/Core/
│       ├── Service/                   # WatchSession + 스트리밍 처리
│       └── Extension/                 # Notification, Color, Date 확장
│
└── Qiri.xcodeproj/                    # Xcode 프로젝트 설정
```

---

## 시작하기

### 요구 사항
- **Xcode 15.0** 이상
- **iOS 16.0** 이상 (iPhone)
- **watchOS 9.0** 이상 (Apple Watch)
- Apple Developer 계정 (실기기 테스트 시)

### 설치 및 실행

1. **저장소 클론**
   ```bash
   git clone https://github.com/kec08/QiriUpdate
   cd QiriUpdate
   ```

2. **Xcode에서 프로젝트 열기**
   ```bash
   open Qiri.xcodeproj
   ```

3. **의존성 설치**
   - Xcode가 Swift Package Manager를 통해 **Moya** 패키지를 자동으로 다운로드합니다.

4. **빌드 타겟 선택**
   - iPhone 앱: `Qiri` 스킴 선택
   - Watch 앱: `Qiri Watch App` 스킴 선택

5. **실행**
   - 시뮬레이터 또는 실기기에서 빌드 & 실행 (⌘+R)
   - Watch 앱은 페어링된 Apple Watch 또는 Watch 시뮬레이터에서 실행

## 사용 방법

### 1. iPhone에서 초기 설정
1. 앱을 실행하고 **Apple로 로그인**합니다.
2. **이용약관에 동의**하면 디바이스가 자동 등록됩니다.
3. 메인 화면에서 **가이드를 따라** AssistiveTouch와 단축어를 설정합니다.

### 2. Apple Watch에서 AI 질문하기
1. Watch 앱을 실행하고 **온보딩을 완료**합니다.
2. 메인 화면에서 **Qiri 영역을 탭**합니다.
3. **음성으로 질문**을 말합니다.
4. AI가 **실시간으로 답변**을 스트리밍합니다.
5. **"더보기"** 로 전체 답변을 확인할 수 있습니다.

### 3. AssistiveTouch 제스처 활용
- iPhone 가이드를 따라 AssistiveTouch를 설정하면, **손 제스처만으로** Watch를 조작할 수 있습니다.
- 화면을 터치하지 않고도 음성 질문을 시작할 수 있습니다.

---

## 핵심 기술 구현

### 실시간 스트리밍 응답
URLSession의 `URLSessionDataDelegate`를 활용하여 서버로부터 SSE(Server-Sent Events) 형식의 응답을 청크 단위로 수신합니다. AI의 사고 과정(`<think>...</think>`)과 최종 답변을 분리하여 각각의 UI에 실시간으로 표시합니다.

### NotificationCenter 이벤트 기반 상태 관리
10개의 커스텀 Notification을 정의하여 네트워크 응답, 화면 전환, 오류 처리 등을 이벤트 기반으로 관리합니다. View는 `.onReceive`로 이벤트를 구독하고 상태를 전환합니다.

### WatchConnectivity 양방향 동기화
- **실시간 메시지**: `sendMessage`로 활성 상태에서 즉시 통신
- **백그라운드 동기화**: `updateApplicationContext`로 비활성 상태에서도 데이터 동기화
- 세션 활성화 시 자동으로 User ID를 동기화하여 끊김 없는 경험 제공

---

## 라이선스

이 프로젝트의 라이선스 정보는 프로젝트 소유자에게 문의하세요.
