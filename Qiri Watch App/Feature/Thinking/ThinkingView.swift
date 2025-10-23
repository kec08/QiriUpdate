import SwiftUI

struct ThinkingView: View {
    @State private var currentChunk: String = "두뇌 회전중..."
    @State private var fullResponse: String = ""
    @State private var isInThinkBlock: Bool = false
    @State private var lastUpdate: Date = Date()

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            ZStack {
                Image("think_speech")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 163, height: 60)
                    .padding(.top, 15)

                Text(currentChunk)
                    .font(.system(size: 13))
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.bottom, -10)

            Image("think_Qiri")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 77)
                .padding(.bottom, 50)
        }
        .frame(maxWidth: .infinity)
        .background(.customBackgroundBlack)
        .foregroundColor(.customWhite)
        .onAppear {
            NotificationCenter.default.addObserver(
                forName: .sttResponseUpdated,
                object: nil,
                queue: .main
            ) { notification in
                if let response = notification.object as? String {
                    handleStreamingResponse(response)
                }
            }
        }
        .onDisappear {
            NotificationCenter.default.removeObserver(self)
        }
    }

    private func handleStreamingResponse(_ response: String) {
        lastUpdate = Date()
        var trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        fullResponse += trimmed + " "

        // <think> 태그 처리
        if trimmed.contains("<think>") {
            isInThinkBlock = true
            trimmed = trimmed.replacingOccurrences(of: "<think>", with: "")
        }

        // </think> 태그 처리
        if trimmed.contains("</think>") {
            isInThinkBlock = false
            trimmed = trimmed.replacingOccurrences(of: "</think>", with: "")
            if !trimmed.isEmpty {
                updateChunk(trimmed)
            }
            finishThinking()
            return
        }

        // <think> 안에 있는 경우 chunk 업데이트
        if isInThinkBlock, !trimmed.isEmpty {
            updateChunk(trimmed)
        }

        // 백업 타임아웃: chunk가 멈춰있으면 1.5초 후 강제로 종료
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if self.isInThinkBlock && Date().timeIntervalSince(self.lastUpdate) > 1.4 {
                self.isInThinkBlock = false
                self.finishThinking()
            }
        }
    }

    private func updateChunk(_ text: String) {
        DispatchQueue.main.async {
            self.currentChunk = text
        }
    }

    private func finishThinking() {
        let cleaned = fullResponse
            .replacingOccurrences(of: "<think>", with: "")
            .replacingOccurrences(of: "</think>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        fullResponse = cleaned
        NotificationCenter.default.post(name: .sttResponseCompleted, object: cleaned)
    }
}
