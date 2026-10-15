import UIKit
import CoreText

enum BATBrand {
    static let purple = UIColor(red: 81/255, green: 42/255, blue: 125/255, alpha: 1)
    static let yellow = UIColor(red: 1, green: 254/255, blue: 15/255, alpha: 1)
}

@main
@MainActor
final class RenderHarness: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        do {
            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let renderer = ScoreboardRenderer()
            var stable = 0
            assert(BATStreamPolicy.bitrate(current: 1_800_000, ceiling: 1_800_000, queue: 2, bytesPerSecond: 150_000, stable: &stable) == 684_000)
            assert(BATStreamPolicy.bitrate(current: 684_000, ceiling: 1_800_000, queue: 10, bytesPerSecond: 0, stable: &stable) == 400_000)
            for _ in 0..<19 { assert(BATStreamPolicy.bitrate(current: 400_000, ceiling: 1_800_000, queue: 0, bytesPerSecond: 250_000, stable: &stable) == 400_000) }
            assert(BATStreamPolicy.bitrate(current: 400_000, ceiling: 1_800_000, queue: 0, bytesPerSecond: 250_000, stable: &stable) == 475_000)
            stable = 19
            assert(BATStreamPolicy.bitrate(current: 1_800_000, ceiling: 1_800_000, queue: 0, bytesPerSecond: 250_000, stable: &stable) == 1_800_000)
            var game = Game.fresh(now: 1000)
            game.home.score = 32; game.home.fouls = 2; game.home.timeouts = 1
            assert(game.apply("opponentPreset", team: nil, value: nil, text: "hub", now: 1000))
            game.away.score = 28; game.away.fouls = 3
            func save(_ name: String) throws {
                NSLog("BAT render check: %@ begin", name)
                guard let cg = renderer.image(for: game, at: 1000), let png = UIImage(cgImage: cg).pngData() else { throw NSError(domain: "Render", code: 1) }
                try png.write(to: folder.appendingPathComponent(name + ".png"))
                NSLog("BAT render check: %@ saved", name)
            }
            try save("broadcast-home-left")
            for dimensions in [CGSize(width: 854, height: 480), CGSize(width: 1280, height: 720), CGSize(width: 1920, height: 1080)] {
                renderer.outputSize = dimensions
                let a = renderer.image(for: game, at: 1000, viewport: CGSize(width: 852, height: 393))!
                let b = renderer.image(for: game, at: 1000, viewport: CGSize(width: 1024, height: 768))!
                assert(a.width == Int(dimensions.width) && a.height == Int(dimensions.height))
                assert(UIImage(cgImage: a).pngData() == UIImage(cgImage: b).pngData(), "Broadcast geometry must be independent of preview")
            }
            renderer.outputSize = CGSize(width: 1920, height: 1080)
            game.homeOnLeft = false; game.quarter = 3; game.clockEnabled = false; game.home.score = 128
            try save("broadcast-home-right-clock-off")
            game.homeOnLeft = true; game.clockEnabled = true; game.quarter = 12; game.home.score = 999; game.away.score = 999
            game.clock = 3600; game.away.logo = "preset:cat"
            try save("broadcast-long-labels")
            // Upgrade compatibility: v38 snapshots do not include team logos or layout fields.
            var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(game)) as! [String: Any]
            legacy.removeValue(forKey: "scoreStyle"); legacy.removeValue(forKey: "homeOnLeft")
            for key in ["home", "away"] { var team = legacy[key] as! [String: Any]; team.removeValue(forKey: "logo"); legacy[key] = team }
            let migrated = try JSONDecoder().decode(Game.self, from: JSONSerialization.data(withJSONObject: legacy))
            assert(migrated.homeOnLeft && migrated.home.logo == "preset:bat" && migrated.home.score == 999)
            guard UIFont(name: "Galiga-Regular", size: 41) != nil else { throw NSError(domain: "Galiga font unavailable", code: 2) }
            var manual = game
            assert(manual.apply("opponentPreset", team: nil, value: nil, text: "vac", now: 1000) && manual.away.name == "VBA")
            assert(manual.apply("opponentPreset", team: nil, value: nil, text: "manual", now: 1000) && manual.away.name.isEmpty && manual.away.logo.isEmpty && manual.away.score == 999)
            game.home.score = 32; game.away.score = 28
            game.caption = "UN TITOLO MOLTO LUNGO DA CONTENERE NEL CARTELLO"
            for kind in ["kiss", "glitter", "timeout", "triple", "cheer", "break", "final", "caption"] {
                assert(game.apply("overlay", team: nil, value: 15, text: kind, now: 1000))
                guard let cg = renderer.image(for: game, at: 1000, viewport: CGSize(width: 852, height: 393)), let png = UIImage(cgImage: cg).pngData() else { throw NSError(domain: "Card render", code: 3) }
                try png.write(to: folder.appendingPathComponent("card-" + kind + ".png"))
            }
            assert(Bundle.main.path(forResource: "kiss-crest", ofType: "png", inDirectory: "BATWeb/broadcast") != nil)
            try "PASS: native rendering, side reversal, clock off, 999, overtime, v38 migration, VBA, manual preset, broadcast cards".write(to: folder.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
        } catch {
            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try? String(describing: error).write(to: folder.appendingPathComponent("error.txt"), atomically: true, encoding: .utf8)
        }
        window = UIWindow(frame: UIScreen.main.bounds); window?.rootViewController = UIViewController(); window?.makeKeyAndVisible()
        return true
    }
}
