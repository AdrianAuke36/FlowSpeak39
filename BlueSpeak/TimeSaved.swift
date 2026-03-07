import Foundation

// Estimates writing time saved by dictation:
// - Typing speed baseline: 40 words/min
// - Speaking speed baseline: 130 words/min
// Saved time = typing time - speaking time
struct TimeSaved {
    static let typingWPM: Double = 40
    static let speakingWPM: Double = 130

    static func seconds(for wordCount: Int) -> Double {
        let words = max(0, Double(wordCount))
        guard typingWPM > 0, speakingWPM > 0 else { return 0 }
        let typingSeconds = (words / typingWPM) * 60
        let speakingSeconds = (words / speakingWPM) * 60
        return max(0, typingSeconds - speakingSeconds)
    }

    static func formatted(for wordCount: Int) -> String {
        let totalSeconds = Int(seconds(for: wordCount).rounded())
        if totalSeconds < 60 {
            return "\(totalSeconds) sec"
        }

        let minutes = totalSeconds / 60
        if minutes < 60 {
            return "\(minutes) min"
        }

        let hours = minutes / 60
        let remainderMinutes = minutes % 60
        if remainderMinutes == 0 {
            return "\(hours) h"
        }
        return "\(hours) h \(remainderMinutes) min"
    }
}
