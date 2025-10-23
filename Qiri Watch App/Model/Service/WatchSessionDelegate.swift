import WatchConnectivity
import Foundation

class WatchSessionDelegate: NSObject, WCSessionDelegate, URLSessionDataDelegate {
    static let shared = WatchSessionDelegate()
    private var isSessionActivated = false
    private var streamingTask: URLSessionDataTask?

    // AnswerMoreView 누적용(think 제거본) 버퍼
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
        guard WCSession.isSupported() else {
            print("WCSession 미지원")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        print("Watch WCSession 활성화 시도")
    }

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        isSessionActivated = (activationState == .activated)
        print("Watch WCSession 활성 상태: \(activationState.rawValue), 오류: \(String(describing: error))")

        if isSessionActivated {
            print("WCSession 활성화 완료")
            if let appleUserId = UserDefaults.standard.string(forKey: "user_id") {
                print("[Watch] 로컬에 저장된 apple_user_id: \(appleUserId)")
            } else {
                // iPhone 연동을 쓰지 않을 계획이면 이 블록은 제거해도 무방합니다.
                session.sendMessage(["request_sync_apple_user_id": true], replyHandler: { reply in
                    if let appleUserId = reply["apple_user_id"] as? String, !appleUserId.isEmpty {
                        UserDefaults.standard.set(appleUserId, forKey: "user_id")
                        print("[Watch] iOS로부터 apple_user_id 수신: \(appleUserId)")
                    }
                }, errorHandler: { error in
                    print("[Watch] ID 동기화 요청 실패: \(error.localizedDescription)")
                })
            }
        }
    }

    // MARK: - 메시지 수신
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        print("받은 메시지: \(message)")
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
        print("받은 메시지 (replyHandler 포함): \(message)")
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Notification.Name("WCSessionMessageReceived"),
                object: nil,
                userInfo: message
            )
        }
        replyHandler(["status": "received"])
    }

    // MARK: - STT 처리
    func processSpeechInput(_ text: String) {
        guard let appleUserId = UserDefaults.standard.string(forKey: "user_id"),
              !appleUserId.isEmpty,
              appleUserId != "unknown_id" else {
            print("[Watch] 사용자 ID 없음")
            NotificationCenter.default.post(name: .sttError, object: "사용자 ID를 확인할 수 없습니다.")
            return
        }

        UserDefaults.standard.set(text, forKey: "last_question")
        sendToBackend(question: text)
    }

    // MARK: - 백엔드 요청
    private func sendToBackend(question: String) {
        guard let appleUserId = UserDefaults.standard.string(forKey: "user_id") else {
            print("[Watch] 사용자 ID 없음")
            NotificationCenter.default.post(name: .sttError, object: "사용자 ID를 확인할 수 없습니다.")
            return
        }

        // 한글 URL 인코딩
        guard let encodedQuestion = question.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedUserId = appleUserId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            print("[Watch] 인코딩 오류")
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
            print("[Watch] URL 구성 실패")
            NotificationCenter.default.post(name: .sttError, object: "인코딩 오류")
            return
        }

        print("[Watch] 요청 URL: \(url.absoluteString)")

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30.0
        configuration.timeoutIntervalForResource = 30.0
        configuration.allowsCellularAccess = true
        configuration.waitsForConnectivity = false

        let session = URLSession(configuration: configuration,
                                 delegate: self,
                                 delegateQueue: OperationQueue.main)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData

        // ✅ 새 요청 전에 누적 본문 초기화
        cleanAccum = ""

        streamingTask?.cancel()
        streamingTask = session.dataTask(with: request)
        streamingTask?.resume()

        print("[Watch] 요청 시작")
        NotificationCenter.default.post(name: .sttCompleted, object: nil)
    }

    // MARK: - URLSession Delegate
    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let httpResponse = response as? HTTPURLResponse {
            print("[Watch] 서버 응답 상태: \(httpResponse.statusCode)")
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        guard let result = String(data: data, encoding: .utf8), !result.isEmpty else { return }
        print("[Watch] 원본 데이터: \(result)")

        // ✅ SSE/평문 모두 처리
        let rawLines = result.components(separatedBy: .newlines)

        for rawLine in rawLines {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            // SSE 형태면 payload만 추출
            if line.hasPrefix("data: ") {
                line = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty { continue }
            }

            // 컨트롤 토큰 처리(서버가 줄 수도 있으니 유지)
            if line == "[streaming started]" {
                NotificationCenter.default.post(name: .sttResponseStarted, object: nil)
                continue
            }
            if line == "[streaming ended]" {
                // ✅ 완료 알림 (누적 본문 전달)
                NotificationCenter.default.post(name: .sttResponseCompleted, object: cleanAccum)
                continue
            }

            // 1) ThinkingView용: 원본 청크 그대로 브로드캐스트 → <think> 파싱/실시간 표시
            NotificationCenter.default.post(name: .sttResponseUpdated, object: line)

            // 2) AnswerMoreView용: think 제거본만 누적/브로드캐스트
            let cleaned = stripThink(from: line).trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                cleanAccum += (cleanAccum.isEmpty ? cleaned : "\n" + cleaned)
                NotificationCenter.default.post(name: .sttCleanResponseUpdated, object: cleaned)
            }
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        let statusCode = (task.response as? HTTPURLResponse)?.statusCode ?? -1

        if let error = error {
            print("[Watch] 스트리밍 완료, 오류: \(error.localizedDescription), HTTP 상태: \(statusCode)")
            NotificationCenter.default.post(name: .sttError, object: "에러 발생: \(error.localizedDescription)")

            if retryCount < maxRetries && statusCode != -1 {
                retryCount += 1
                print("[Watch] 리트라이 \(retryCount)/\(maxRetries)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if let question = UserDefaults.standard.string(forKey: "last_question") {
                        self.sendToBackend(question: question)
                    }
                }
            }
        } else {
            print("[Watch] 스트리밍 완료, HTTP 상태: \(statusCode), 전체 응답(think 제거): \(cleanAccum)")
            // ✅ 서버가 [streaming ended]를 안 줘도 완료 알림 보장
            NotificationCenter.default.post(name: .sttResponseCompleted, object: cleanAccum)
        }

        streamingTask = nil
        UserDefaults.standard.removeObject(forKey: "last_question")
        retryCount = 0
        // ❗️cleanAccum 초기화 금지 (AnswerMoreView에서 프리로드 필요)
        // 초기화는 새 요청 시작 시(sendToBackend)에서만 수행
    }

    // MARK: - Utils
    /// <think> 블록 전체 제거
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

    /// AnswerMoreView 진입 시, 지금까지 누적된 think-제거 본문을 돌려줌
    func currentCleanAccum() -> String {
        return cleanAccum
    }
}

