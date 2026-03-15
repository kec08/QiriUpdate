import SwiftUI

struct AnswerMoreView: View {
    @Environment(\.dismiss) private var back
    @State private var displayText = ""
    @State private var isStreaming = true

    // 단어 스트리밍 관리
    @State private var pendingWords: [String] = []
    @State private var streamTask: Task<Void, Never>? = nil
    private let wordDelay: UInt64 = 400_000_000 // 0.40초

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    // 제목 살짝 작게
                    Text("Qiri의 답변")
                        .font(.system(size: 18, weight: .semibold))
                        .padding(.bottom, 2)

                    bullet(displayText)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(8)
                        .id("bottom") // 자동 스크롤

                    HStack {
                        Spacer()
                        Button("확인") {
                            NotificationCenter.default.post(name: .returnToMain, object: nil)
                            back()
                        }
                        .frame(width: 120, height: 40)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                        .shadow(radius: 2)
                        .padding(.top, 20)
                        Spacer()
                    }
                }
                // 좌우 마진
                .padding(.horizontal, 5)
                .padding(.vertical, 8)
            }
            .background(Color.customBackgroundBlack)

            .onAppear {
                let initial = WatchSessionDelegate.shared
                    .currentCleanAccum()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !initial.isEmpty {
                    displayText = sanitize(initial)
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }

            // 스트리밍 청크 수신
            .onReceive(NotificationCenter.default.publisher(for: .sttCleanResponseUpdated)) { notification in
                guard let chunk = notification.object as? String else { return }
                let clean = sanitize(chunk)
                guard !clean.isEmpty else { return }
                enqueueChunk(clean)

                // 새 토큰 들어올 때마다 하단 스크롤
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }

            // 스트리밍 완료
            .onReceive(NotificationCenter.default.publisher(for: .sttResponseCompleted)) { _ in
                isStreaming = false
            }

            .onDisappear {
                streamTask?.cancel()
                streamTask = nil
            }
        }
    }

    // MARK: - 스트리밍 대기열
    private func enqueueChunk(_ text: String) {
        let words = tokenize(text)
        guard !words.isEmpty else { return }

        if !displayText.isEmpty, !displayText.hasSuffix("\n") {
            pendingWords.append("\n")
        }
        pendingWords.append(contentsOf: words)
        startStreamingIfNeeded()
    }

    private func startStreamingIfNeeded() {
        guard streamTask == nil else { return }
        streamTask = Task { @MainActor in
            defer { streamTask = nil }
            while !Task.isCancelled {
                if pendingWords.isEmpty {
                    try? await Task.sleep(nanoseconds: 20_000_000)
                    continue
                }
                let token = pendingWords.removeFirst()
                displayText += (token == "\n" ? "\n" : token + " ")
                try? await Task.sleep(nanoseconds: wordDelay)
            }
        }
    }

    // 공백/개행 보존 토큰화
    private func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).forEach { line in
            let rawWords = line.split(separator: " ").map { String($0) }.filter { !$0.isEmpty }
            if rawWords.isEmpty {
                tokens.append("\n")
            } else {
                var prepared: [String] = []
                for (i, w) in rawWords.enumerated() {
                    if i == 0, isListMarker(w) {
                        prepared.append(w)
                    } else {
                        prepared.append(w)
                    }
                }
                tokens.append(contentsOf: prepared)
                tokens.append("\n")
            }
        }
        while tokens.last == "\n" { _ = tokens.popLast() }
        return tokens
    }

    private func isListMarker(_ w: String) -> Bool {
        if w == "-" || w == "*" || w == "•" { return true }
        if let first = w.first, first.isNumber, w.hasSuffix(".") { return true }
        return false
    }

    // MARK: - 필터 + 안전장치(<think> 제거 포함)
    private func sanitize(_ text: String) -> String {
        // 디버그 로그/잡텍스트 필터
        let bannedSubstrings = [
            "스트리밍 완료 응답 수신",
            "[Watch] 원본 데이터",
            "[Watch] 스트리밍 완료",
            "WCSession",
            "activationState"
        ]
        for b in bannedSubstrings where text.contains(b) {
            return ""
        }
        // <think> 제거
        return removeThinkTags(from: text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func removeThinkTags(from text: String) -> String {
        var result = text
        while let s = result.range(of: "<think>"),
              let e = result.range(of: "</think>"),
              s.lowerBound < e.upperBound {
            result.removeSubrange(s.lowerBound..<e.upperBound)
        }
        result = result.replacingOccurrences(of: "<think>", with: "")
                       .replacingOccurrences(of: "</think>", with: "")
        return result
    }

    // MARK: - 기존 UI 유지 (본문 폰트만 축소)
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").bold().font(.system(size: 14))
            Text(text)
                .font(.system(size: 15))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.footnote)
    }
}

