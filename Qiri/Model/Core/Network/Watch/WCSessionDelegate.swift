import Foundation
import WatchConnectivity
import SwiftUI

// MARK: - ㅎ
// iPhone, Apple Watch 간의 WatchConnectivity 통신을 관리하는 싱글톤 클래스
// WCSessionDelegate를 채택하여 세션 상태 변화 및 메시지 수신 이벤트를 처리
final class WatchSessionDelegate: NSObject, WCSessionDelegate {

    // MARK: - 싱글톤 인스턴스
    // 앱 전체에서 하나의 인스턴스만 사용
    static let shared = WatchSessionDelegate()

    // MARK: - 상태 프로퍼티
    private var isSessionActivated = false   // WCSession 활성화 여부
    private var retryCount = 0               // user_id 재시도 카운트
    private let maxRetries = 3

    // MARK: - 초기화
    // private으로 외부 인스턴스 생성 차단 (싱글톤 패턴 강제)
    // 초기화 즉시 WCSession 활성화
    private override init() {
        super.init()
        activateSession()
    }

    // MARK: - WCSession 활성화
    // WCSession이 지원되는 기기인지 확인 후 세션을 활성화
    // iPhone에서만 동작하며, iPad는 WCSession 미지원
    private func activateSession() {
        guard WCSession.isSupported() else {
            print("WCSession 미지원")
            return
        }
        let session = WCSession.default
        session.delegate = self   // self 지정하여 콜백 수신
        session.activate()
        print("iOS WCSession 활성화 시도")
    }

    // MARK: - 메시지 수신 (replyHandler X)
    // 워치가 sendMessage(_:replyHandler:) 호출 시 replyHandler를 nil로 보낸 경우 호출됨
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleMessage(message)
    }

    // MARK: - 메시지 수신 (replyHandler O)
    // 워치가 응답을 기대하며 메시지를 보낸 경우 호출됨
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handleMessage(message, replyHandler: replyHandler)
    }

    // MARK: - 메시지 공통 처리
    // 수신된 메시지 딕셔너리의 키를 분기하여 각 상황에 맞게 처리
    private func handleMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)? = nil) {
        let session = WCSession.default
        print("iOS 메시지 수신: \(message), isReachable=\(session.isReachable), activationState=\(session.activationState.rawValue)")

        // 로그 메시지 처리
        // 워치가 log + source 키를 함께 보낸 경우
        if let log = message["log"] as? String, let source = message["source"] as? String {
            print("[\(source)] \(log)")
            
            // 워치에서 미등록 디바이스 알림이 온 경우
            // 메인 스레드에서 NotificationCenter로 UI 이벤트 발송
            if source == "watch", let registration = message["registration"] as? String, registration == "not_registered" {
                print("[iOS] 디바이스 등록 안 됨 - 약관 동의 필요")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .deviceNotRegistered, object: nil)
                }
                if let replyHandler = replyHandler {
                    let response = ["log": "등록 필요 확인", "source": "ios"]
                    replyHandler(response)
                }
            }

        // 워치가 apple_user_id 동기화를 요청한 경우
        // 워치 앱이 최초 실행되거나 ID가 없을 때 iOS에 요청을 보냄
        } else if let requestSyncAppleUserId = message["request_sync_apple_user_id"] as? Bool, requestSyncAppleUserId == true {
            sendAppleUserIdToWatch(replyHandler: replyHandler)

        // 워치가 역으로 apple_user_id를 iOS로 보낸 경우 - 수신 확인
        } else if let appleUserIdFromWatch = message["apple_user_id"] as? String {
            print("[iOS] 워치로부터 apple_user_id 수신: \(appleUserIdFromWatch)")
            if let replyHandler = replyHandler {
                let response = ["log": "apple_user_id 수신 완료", "source": "ios"]
                replyHandler(response)
            }

        // 정의되지 않은 메시지 포맷 — 에러 응답 반환
        } else {
            print("[iOS] 예상치 못한 메시지 형식: \(message)")
            if let replyHandler = replyHandler {
                let errorResponse = ["log": "잘못된 메시지 형식", "source": "ios"]
                replyHandler(errorResponse)
            }
        }
    }

    // MARK: - Apple User ID를 워치로 전송
    // UserDefaults에서 user_id를 읽어 워치에 sendMessage로 전달 3초 간격으로 재시도
    func sendAppleUserIdToWatch(replyHandler: (([String: Any]) -> Void)? = nil) {
        // UserDefaults에서 로그인된 사용자 ID 조회
        let appleUserId = UserDefaults.standard.string(forKey: "user_id") ?? "unknown_id"
        let session = WCSession.default

        // isReachable: 워치가 현재 Bluetooth 범위 내에 있고 앱이 실행 중인 경우에만 true
        if session.isReachable {
            let message = ["apple_user_id": appleUserId, "source": "ios"]
            session.sendMessage(message, replyHandler: { reply in
                print("[iOS] apple_user_id 전송 성공: \(reply)")
                self.retryCount = 0

                // applicationContext 업데이트: 워치가 백그라운드거나 연결이 끊어져 있어도
                // 다음 번에 연결됐을 때 최신 user_id를 받을 수 있도록 백업 동기화
                do {
                    try session.updateApplicationContext(["user_id": appleUserId])
                    print("[iOS] user_id applicationContext에 업데이트: \(appleUserId)")
                } catch {
                    print("[iOS] applicationContext 업데이트 실패: \(error.localizedDescription)")
                }

                // 원래 요청자(워치 또는 내부 로직)에게 전달 완료 응답
                if let replyHandler = replyHandler {
                    let response: [String: Any] = [
                        "log": "apple_user_id 전달 완료",
                        "apple_user_id": appleUserId,
                        "source": "ios"
                    ]
                    replyHandler(response)
                }
            }, errorHandler: { error in
                print("[iOS] apple_user_id 전송 실패: \(error.localizedDescription)")

                // 재시도 로직
                if self.retryCount < self.maxRetries {
                    self.retryCount += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        self.sendAppleUserIdToWatch(replyHandler: replyHandler)
                    }
                } else {
                    // 3회 모두 실패 시 replyHandler에 실패 응답 반환
                    if let replyHandler = replyHandler {
                        replyHandler([
                            "log": "apple_user_id 전송 재시도 실패",
                            "source": "ios"
                        ])
                    }
                }
            })
        } else {
            // 워치가 현재 연결 불가능한 상태
            print("[iOS] 워치와 연결 안 됨, apple_user_id 전송 불가")
            if let replyHandler = replyHandler {
                replyHandler([
                    "log": "워치 연결 불가",
                    "source": "ios"
                ])
            }
        }
    }

    // MARK: - WCSession 상태 변화 콜백
    // Apple Watch가 교체되거나 새 페어링이 시작될 때 호출 - 이 상태에서는 메시지 전송 불가
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("iOS WCSession 비활성화")
    }

    // 여기서 WCSession.default.activate()를 다시 호출해 새 세션을 시작할 수 있음
    func sessionDidDeactivate(_ session: WCSession) {
        print("iOS WCSession 비활성화 완료")
    }

    // MARK: - 세션 활성화 완료 콜백
    // activate() 호출 후 비동기로 실행
    // 활성화 성공 + 워치 연결 가능 상태면 즉시 apple_user_id 자동 전송
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        isSessionActivated = (activationState == .activated)
        print("iOS WCSession 활성 상태: \(activationState.rawValue), 오류: \(String(describing: error))")

        // 세션 준비 완료 시 자동으로 사용자 ID 동기화 시도
        if isSessionActivated && session.isReachable {
            print("WCSession 활성화 및 연결 가능")
            sendAppleUserIdToWatch()
        }
    }
}
