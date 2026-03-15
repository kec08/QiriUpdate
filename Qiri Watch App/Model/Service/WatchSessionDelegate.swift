import WatchConnectivity
import Foundation

class WatchSessionDelegate: NSObject, WCSessionDelegate, URLSessionDataDelegate {
    static let shared = WatchSessionDelegate()
    private var isSessionActivated = false
    private var streamingTask: URLSessionDataTask?

    // AnswerMoreView가 onAppear 시 프리로드하는 버퍼
    // 새 요청 전에만 초기화 — 완료 후에는 절대 건드리지 않음
    private var cleanAccum = ""

    private let maxRetries = 3
    private var retryCount = 0

    private override init() {
        super.init()
        activateSession()
    }

    private var baseURL: URL {
        return URL(string: "http://qiri.kro.kr:10000/")!
    }

    // MARK: - WCSession 설정
    private func activateSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        isSessionActivated = (activationState == .activated)

        if isSessionActivated {
            if let appleUserId = UserDefaults.standard.string(forKey: "user_id") {
                // 로컬에 저장된 ID가 있으면 iPhone 동기화 불필요
                print("[Watch] 로컬에 저장된 apple_user_id: \(appleUserId)")
            } else {
                // 저장된 ID 없음 → iPhone에 동기화 요청
                // iOS WatchSessionDelegate.sendAppleUserIdToWatch()가 응답
                session.sendMessage(["request_sync_apple_user_id": true], replyHandler: { reply in
                    if let appleUserId = reply["apple_user_id"] as? String, !appleUserId.isEmpty {
                        UserDefaults.standard.set(appleUserId, forKey: "user_id")
                    }
                }, errorHandler: { error in
                    print("[Watch] ID 동기화 요청 실패: \(error.localizedDescription)")
                })
            }
        }
    }

    // MARK: - 메시지 수신
    // iPhone으로부터 메시지가 오면 NotificationCenter로 브로드캐스트
    // RootView에서 .deviceNotRegistered 등 처리
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Notification.Name("WCSessionMessageReceived"),
                object: nil,
                userInfo: message
            )
        }
    }

    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Notification.Name("WCSessionMessageReceived"),
                object: nil,
                userInfo: message
            )
        }
        replyHandler(["status": "received"]) // replyHandler는 반드시 호출해야 iPhone 쪽 타임아웃 방지
    }

    // MARK: - STT 처리
    func processSpeechInput(_ text: String) {
        // userId 없으면 백엔드 요청 자체를 막음
        guard let appleUserId = UserDefaults.standard.string(forKey: "user_id"),
              !appleUserId.isEmpty,
              appleUserId != "unknown_id" else {
            NotificationCenter.default.post(name: .sttError, object: "사용자 ID를 확인할 수 없습니다.")
            return
        }

        // 재시도 시 질문을 다시 꺼내 쓸 수 있도록 미리 저장
        UserDefaults.standard.set(text, forKey: "last_question")
        sendToBackend(question: text)
    }

    // MARK: - 백엔드 요청
    private func sendToBackend(question: String) {
        guard let appleUserId = UserDefaults.standard.string(forKey: "user_id") else {
            NotificationCenter.default.post(name: .sttError, object: "사용자 ID를 확인할 수 없습니다.")
            return
        }

        // 한글 등 특수문자가 포함된 질문을 URL에 안전하게 담기 위해 인코딩
        guard let encodedQuestion = question.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedUserId = appleUserId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            NotificationCenter.default.post(name: .sttError, object: "인코딩 오류")
            return
        }

        var components = URLComponents()
        components.scheme = baseURL.scheme
        components.host = baseURL.host
        components.port = baseURL.port
        components.path = "/ask"
        components.queryItems = [
            URLQueryItem(name: "q", value: encodedQuestion),
            URLQueryItem(name: "apple_user_id", value: encodedUserId),
        ]

        guard let url = components.url else {
            NotificationCenter.default.post(name: .sttError, object: "인코딩 오류")
            return
        }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30.0
        configuration.timeoutIntervalForResource = 30.0
        configuration.allowsCellularAccess = true
        configuration.waitsForConnectivity = false  // 연결될 때까지 기다리지 않고 바로 실패 처리

        // delegate를 self로 지정해야 didReceive data 등 스트리밍 콜백을 받을 수 있음
        let session = URLSession(configuration: configuration,
                                 delegate: self,
                                 delegateQueue: OperationQueue.main)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData  // 이전 캐시 무시, 항상 새 응답 수신

        // 새 요청 전 반드시 초기화 — 이전 응답이 섞이는 것 방지
        cleanAccum = ""
        streamingTask?.cancel()  // 진행 중인 이전 요청 취소
        streamingTask = session.dataTask(with: request)
        streamingTask?.resume()

        // 요청 시작을 알림 → RootView가 .thinking 화면으로 전환
        NotificationCenter.default.post(name: .sttCompleted, object: nil)
    }

    // MARK: - URLSession Delegate (스트리밍 수신)

    // 서버 응답 헤더 수신 시 호출 — .allow를 반환해야 body 수신이 시작됨
    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        completionHandler(.allow)
    }

    // 서버에서 데이터 청크가 올 때마다 반복 호출됨 (스트리밍 핵심)
    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        guard let result = String(data: data, encoding: .utf8), !result.isEmpty else { return }

        let rawLines = result.components(separatedBy: .newlines)

        for rawLine in rawLines {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            // SSE 형식("data: 내용")이면 "data: " 접두어 제거 후 payload만 사용
            if line.hasPrefix("data: ") {
                line = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty { continue }
            }

            // 서버 컨트롤 토큰 처리
            if line == "[streaming started]" {
                NotificationCenter.default.post(name: .sttResponseStarted, object: nil)
                continue
            }
            if line == "[streaming ended]" {
                NotificationCenter.default.post(name: .sttResponseCompleted, object: cleanAccum)
                continue
            }

            // 두 갈래로 나눠서 각각 다른 View에 전달
            // ThinkingView: <think> 포함 원본 → 추론 과정을 실시간으로 보여줌
            NotificationCenter.default.post(name: .sttResponseUpdated, object: line)

            // AnswerMoreView: <think> 제거한 정제본만 누적
            let cleaned = stripThink(from: line).trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                cleanAccum += (cleanAccum.isEmpty ? cleaned : "\n" + cleaned)
                NotificationCenter.default.post(name: .sttCleanResponseUpdated, object: cleaned)
            }
        }
    }

    // 스트리밍 완료 또는 오류 시 호출
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        let statusCode = (task.response as? HTTPURLResponse)?.statusCode ?? -1

        if let error = error {
            NotificationCenter.default.post(name: .sttError, object: "에러 발생: \(error.localizedDescription)")

            // 네트워크 오류 시 최대 3회, 2초 간격으로 자동 재시도
            if retryCount < maxRetries && statusCode != -1 {
                retryCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if let question = UserDefaults.standard.string(forKey: "last_question") {
                        self.sendToBackend(question: question)
                    }
                }
            }
        } else {
            // [streaming ended]가 오지 않은 경우를 대비한 완료 알림 보장
            NotificationCenter.default.post(name: .sttResponseCompleted, object: cleanAccum)
        }

        streamingTask = nil
        UserDefaults.standard.removeObject(forKey: "last_question")
        retryCount = 0
        // cleanAccum은 여기서 초기화 금지
        // AnswerMoreView가 onAppear에서 currentCleanAccum()으로 프리로드하기 때문
    }

    // MARK: - Utils

    // <think>...</think> 블록 전체 제거
    // 한 청크 안에 태그가 여러 개 있을 수 있어서 while로 반복 처리
    private func stripThink(from text: String) -> String {
        var out = text
        while let s = out.range(of: "<think>"),
              let e = out.range(of: "</think>"),
              s.lowerBound < e.upperBound {
            out.removeSubrange(s.lowerBound..<e.upperBound)
        }
        out = out.replacingOccurrences(of: "<think>", with: "")
                 .replacingOccurrences(of: "</think>", with: "")
        return out
    }

    // AnswerMoreView가 onAppear 시 호출 — 스트리밍 중이어도 지금까지 누적된 내용 즉시 표시 가능
    func currentCleanAccum() -> String {
        return cleanAccum
    }
}
