import Foundation

struct Team: Codable {
    var name: String
    var color: String
    var logo: String
    var score: Int
    var fouls: Int
    var timeouts: Int
}

struct Game: Codable {
    var home: Team
    var away: Team
    var quarter: Int
    var clock: Double
    var running: Bool
    var startedAt: Double
    var overlay: String
    var overlayUntil: Double
    var caption: String
    var showScore: Bool
    var live: Bool
    var liveCommand: Double

    func remaining(at serverNow: Double) -> Int {
        var value = clock - (running ? (serverNow - startedAt) / 1000 : 0)
        return max(0, Int(ceil(value)))
    }

    func clockText(at serverNow: Double) -> String {
        var seconds = remaining(at: serverNow)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func visibleOverlay(at serverNow: Double) -> String {
        overlayUntil > 0 && serverNow > overlayUntil ? "" : overlay
    }
}

struct MatchSnapshot: Decodable {
    var state: Game
    var revision: Int
    var serverNow: Double
}

enum CameraIssue: LocalizedError {
    case noMatch
    case bluetooth
    case invalidURL
    case noKey
    case noCamera
    case network(Int)

    var errorDescription: String? {
        switch self {
        case .noMatch: "Inserisci il codice della partita creato sul tablet."
        case .bluetooth: "Attiva Bluetooth e collega BAT tv Regia sul tablet."
        case .invalidURL: "Copia l’indirizzo RTMPS completo da Facebook Live Producer."
        case .noKey: "Inserisci la chiave della diretta di Facebook."
        case .noCamera: "Consenti l’accesso a camera e microfono nelle Impostazioni iPhone."
        case .network(let code): "La partita non è raggiungibile (HTTP \(code))."
        }
    }
}

// The camera holds the authoritative game, including the clock. A radio interruption
// never resets the match or stops the Facebook stream.
extension Game {
    static func fresh(now: Double) -> Game {
        Game(home: Team(name: "BAT", color: "#512A7D", logo: "", score: 0, fouls: 0, timeouts: 0),
             away: Team(name: "AVVERSARI", color: "#FFFE0F", logo: "", score: 0, fouls: 0, timeouts: 0),
             quarter: 1, clock: 600, running: false, startedAt: now,
             overlay: "", overlayUntil: 0, caption: "", showScore: true, live: false, liveCommand: 0)
    }

    mutating func apply(_ action: String, team: String?, value: Int?, text: String?, now: Double) -> Bool {
        switch action {
        case "score", "foul", "timeout":
            guard let team, ["home", "away"].contains(team), let value, (-3...3).contains(value) else { return false }
            var target = team == "home" ? home : away
            switch action {
            case "score": target.score = min(999, max(0, target.score + value))
            case "foul": target.fouls = min(99, max(0, target.fouls + value))
            default: target.timeouts = min(99, max(0, target.timeouts + value))
            }
            if team == "home" { home = target } else { away = target }
        case "clockStart":
            if !running && clock > 0 { running = true; startedAt = now }
        case "clockStop":
            clock = Double(remaining(at: now)); running = false; startedAt = now
        case "clockSet":
            guard let value, (0...3600).contains(value) else { return false }
            clock = Double(value); startedAt = now; running = false
        case "quarter":
            guard let value, (1...12).contains(value) else { return false }
            quarter = value
        case "overlay":
            guard let text, ["", "kiss", "triple", "break", "final", "caption"].contains(text) else { return false }
            overlay = text; overlayUntil = (value ?? 0) > 0 ? now + Double(min(value ?? 0, 300)) * 1000 : 0
        case "caption": caption = String((text ?? "").prefix(100)); overlay = "caption"; overlayUntil = 0
        case "showScore": showScore = value != 0
        case "rename":
            guard let team, ["home", "away"].contains(team), let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            if team == "home" { home.name = String(text.prefix(24)) } else { away.name = String(text.prefix(24)) }
        default: return false
        }
        return true
    }
}
