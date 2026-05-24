import Foundation

@MainActor
final class ResponseDisplayDriver {
    private weak var message: MessageEntity?
    private let mode: LiveDisplayMode
    private let charactersPerSecond: Int

    private var targetText = ""
    private var visibleText = ""
    private var animationTask: Task<Void, Never>?

    init(message: MessageEntity, mode: LiveDisplayMode, charactersPerSecond: Int) {
        self.message = message
        self.mode = mode
        self.charactersPerSecond = max(30, min(charactersPerSecond, 180))
    }

    func updateTarget(_ text: String) {
        targetText = text

        switch mode {
        case .rawStream:
            visibleText = text
            message?.text = text
        case .instant:
            break
        case .smoothLive:
            startAnimationIfNeeded()
        }
    }

    func finish(finalText: String) async {
        targetText = finalText

        switch mode {
        case .rawStream, .instant:
            visibleText = finalText
            message?.text = finalText
        case .smoothLive:
            startAnimationIfNeeded(fastFinish: true)
            while visibleText != targetText {
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
    }

    func cancel() {
        animationTask?.cancel()
        animationTask = nil
    }

    private func startAnimationIfNeeded(fastFinish: Bool = false) {
        guard animationTask == nil else { return }

        animationTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled, self.visibleText != self.targetText {
                let step = self.stepSize(fastFinish: fastFinish)
                self.visibleText = self.nextVisibleText(step: step)
                self.message?.text = self.visibleText
                try? await Task.sleep(nanoseconds: self.frameDelayNanoseconds)
            }

            self.animationTask = nil
        }
    }

    private func nextVisibleText(step: Int) -> String {
        guard visibleText.count < targetText.count else { return targetText }
        let nextCount = min(targetText.count, visibleText.count + step)
        let index = targetText.index(targetText.startIndex, offsetBy: nextCount)
        return String(targetText[..<index])
    }

    private func stepSize(fastFinish: Bool) -> Int {
        let base = max(1, charactersPerSecond / 30)
        let backlog = max(0, targetText.count - visibleText.count)
        if fastFinish { return max(base * 3, 8) }
        if backlog > 500 { return max(base * 3, 8) }
        if backlog > 200 { return max(base * 2, 5) }
        return base
    }

    private var frameDelayNanoseconds: UInt64 {
        33_000_000
    }
}
