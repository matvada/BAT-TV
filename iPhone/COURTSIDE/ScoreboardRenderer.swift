import UIKit

@MainActor
final class ScoreboardRenderer {
    private let size = CGSize(width: 1280, height: 720)
    private let outputSize = CGSize(width: 1920, height: 1080)
    private let ink = UIColor.white
    // The banner artwork already contains a high resolution logo. Use a tight
    // crop so the lettering fills the small channel bug in the broadcast.
    private lazy var channelLogo: UIImage? = {
        guard let image = UIImage(named: "BATLogo")?.cgImage,
              let crop = image.cropping(to: CGRect(x: 94, y: 65, width: 718, height: 718)) else { return nil }
        return UIImage(cgImage: crop)
    }()
    // Only the bat artwork in the upper portion is used. The lower BAT letters
    // and the white background never become a visible part of the score bar.
    private lazy var scoreWatermark: UIImage? = {
        guard let source = UIImage(named: "BATWatermark")?.cgImage,
              let bat = source.cropping(to: CGRect(x: 0, y: 0, width: source.width, height: min(960, source.height)))
        else { return nil }
        return UIImage(cgImage: bat)
    }()

    func image(for game: Game, at serverNow: Double) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: outputSize, format: format).image { context in
            let cg = context.cgContext
            cg.scaleBy(x: outputSize.width / size.width, y: outputSize.height / size.height)
            if game.showScore { drawScore(game, at: serverNow, in: cg) }
            switch game.visibleOverlay(at: serverNow) {
            case "kiss": drawKiss(in: cg)
            case "triple": drawTriple(in: cg, at: serverNow)
            case "cheer": drawCheer(in: cg, at: serverNow, until: game.overlayUntil)
            case "break", "final":
                fill(CGRect(origin: .zero, size: size), BATBrand.purple.withAlphaComponent(0.9), in: cg)
                fill(CGRect(x: 170, y: 205, width: 940, height: 260), UIColor.black.withAlphaComponent(0.27), in: cg)
                fill(CGRect(x: 170, y: 205, width: 10, height: 260), BATBrand.yellow, in: cg)
                label(game.overlay == "final" ? "FINE PARTITA" : "INTERVALLO", in: CGRect(x: 205, y: 238, width: 870, height: 104), size: 76)
                label("\(game.home.name)  \(game.home.score) – \(game.away.score)  \(game.away.name)", in: CGRect(x: 220, y: 350, width: 840, height: 75), size: 38, color: BATBrand.yellow)
            case "caption":
                fill(CGRect(x: 58, y: 400, width: 1164, height: 90), BATBrand.purple.withAlphaComponent(0.96), in: cg)
                fill(CGRect(x: 58, y: 400, width: 9, height: 90), BATBrand.yellow, in: cg)
                label(game.caption, in: CGRect(x: 86, y: 410, width: 1108, height: 70), size: 45, alignment: .left)
            default: break
            }
            drawChannel(in: cg)
        }
        return image.cgImage
    }

    private func drawChannel(in cg: CGContext) {
        let rect = CGRect(x: 1168, y: 31, width: 64, height: 64)
        cg.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: 15).addClip()
        cg.interpolationQuality = .high
        channelLogo?.draw(in: rect)
        cg.restoreGState()
    }

    private func drawScore(_ game: Game, at now: Double, in cg: CGContext) {
        cg.saveGState()
        cg.translateBy(x: 0, y: 42)
        let bar = CGRect(x: 190, y: 600, width: 900, height: 64)
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [UIColor(red: 86/255, green: 49/255, blue: 136/255, alpha: 0.96).cgColor,
                                              UIColor(red: 73/255, green: 37/255, blue: 118/255, alpha: 0.96).cgColor] as CFArray,
                                     locations: [0, 1]) {
            cg.saveGState()
            cg.clip(to: bar)
            cg.drawLinearGradient(gradient, start: CGPoint(x: bar.midX, y: bar.minY),
                                  end: CGPoint(x: bar.midX, y: bar.maxY), options: [])
            cg.restoreGState()
        }
        cg.saveGState()
        cg.clip(to: bar)
        scoreWatermark?.draw(in: CGRect(x: 416, y: 521, width: 448, height: 270), blendMode: .multiply, alpha: 0.14)
        cg.restoreGState()
        fill(CGRect(x: 190, y: 600, width: 7, height: 64), color(game.home.color), in: cg)
        fill(CGRect(x: 1083, y: 600, width: 7, height: 64), color(game.away.color), in: cg)
        label(String(game.home.name.prefix(3)).uppercased(), in: CGRect(x: 198, y: 608, width: 100, height: 49), size: 31)
        drawFouls(game.home.fouls, x: 327, y: 632, in: cg)
        label("\(game.home.score)", in: CGRect(x: 421, y: 595, width: 118, height: 70), size: 52)
        label("\(game.away.score)", in: CGRect(x: 741, y: 595, width: 118, height: 70), size: 52)
        drawFouls(game.away.fouls, x: 897, y: 632, in: cg)
        label(String(game.away.name.prefix(3)).uppercased(), in: CGRect(x: 982, y: 608, width: 100, height: 49), size: 31)
        let quarter = game.quarter <= 4 ? "Q\(game.quarter)" : "OT\(game.quarter - 4)"
        if game.clockEnabled {
            label(game.clockText(at: now), in: CGRect(x: 550, y: 598, width: 180, height: 40), size: 30, color: BATBrand.yellow)
            label(quarter, in: CGRect(x: 550, y: 633, width: 180, height: 26), size: 16, color: .lightGray)
        } else {
            label(quarter, in: CGRect(x: 530, y: 592, width: 220, height: 80), size: 56, color: BATBrand.yellow)
        }
        cg.restoreGState()
    }

    private func drawFouls(_ fouls: Int, x: CGFloat, y: CGFloat, in cg: CGContext) {
        for index in 0..<5 {
            let circle = CGRect(x: x + CGFloat(index * 14) - 5, y: y - 5, width: 10, height: 10)
            cg.addEllipse(in: circle)
            if index < fouls {
                cg.setFillColor((index == 4 ? UIColor.systemRed : BATBrand.yellow).cgColor)
                cg.fillPath()
            } else {
                cg.setStrokeColor(UIColor.white.withAlphaComponent(0.7).cgColor)
                cg.setLineWidth(1.5)
                cg.strokePath()
            }
        }
    }

    private func drawKiss(in cg: CGContext) {
        cg.setStrokeColor(BATBrand.yellow.cgColor)
        cg.setLineWidth(12)
        cg.setShadow(offset: .zero, blur: 14, color: BATBrand.yellow.withAlphaComponent(0.85).cgColor)
        let border = UIBezierPath(roundedRect: CGRect(x: 30, y: 80, width: 1220, height: 560), cornerRadius: 32)
        cg.addPath(border.cgPath)
        cg.strokePath()
        cg.setShadow(offset: .zero, blur: 0)
        fill(CGRect(x: 350, y: 80, width: 580, height: 100), BATBrand.purple.withAlphaComponent(0.95), in: cg)
        label("♥  KISS CAM  ♥", in: CGRect(x: 375, y: 82, width: 530, height: 94), size: 58)
        label("♥", in: CGRect(x: 85, y: 160, width: 115, height: 100), size: 92, color: BATBrand.yellow)
        label("♥", in: CGRect(x: 1080, y: 160, width: 115, height: 100), size: 92, color: BATBrand.yellow)
    }

    private func drawTriple(in cg: CGContext, at now: Double) {
        let pulse = 1 + CGFloat(sin(now / 170)) * 0.018
        cg.saveGState()
        defer { cg.restoreGState() }
        cg.translateBy(x: 640, y: 325)
        cg.scaleBy(x: pulse, y: pulse)
        cg.translateBy(x: -640, y: -325)
        for index in 0..<14 {
            let angle = Double(index) * (.pi * 2 / 14) + (now / 900).truncatingRemainder(dividingBy: .pi * 2)
            let inner: CGFloat = 187
            let outer: CGFloat = index.isMultiple(of: 2) ? 234 : 218
            let dx = CGFloat(cos(angle))
            let dy = CGFloat(sin(angle))
            cg.setStrokeColor(BATBrand.yellow.withAlphaComponent(index.isMultiple(of: 2) ? 0.9 : 0.55).cgColor)
            cg.setLineWidth(index.isMultiple(of: 2) ? 10 : 5)
            cg.setLineCap(.round)
            cg.move(to: CGPoint(x: 640 + dx * inner, y: 325 + dy * inner))
            cg.addLine(to: CGPoint(x: 640 + dx * outer, y: 325 + dy * outer))
            cg.strokePath()
        }
        fill(CGRect(x: 272, y: 204, width: 736, height: 242), BATBrand.yellow, in: cg)
        fill(CGRect(x: 279, y: 211, width: 722, height: 228), BATBrand.purple, in: cg)
        fill(CGRect(x: 296, y: 227, width: 204, height: 196), BATBrand.yellow, in: cg)
        label("+3", in: CGRect(x: 305, y: 232, width: 186, height: 174), size: 137, color: .black)
        label("TRIPLA!", in: CGRect(x: 520, y: 239, width: 456, height: 112), size: 88)
        label("BOMBA DA TRE", in: CGRect(x: 533, y: 353, width: 430, height: 55), size: 36, color: BATBrand.yellow)
    }

    private func drawCheer(in cg: CGContext, at now: Double, until: Double) {
        let enter = min(1, max(0, (now - (until - 8000)) / 650))
        let exit = min(1, max(0, (until - now) / 500))
        let slide = CGFloat(-1150 * (1 - enter) + 1150 * (1 - exit))
        cg.saveGState()
        defer { cg.restoreGState() }
        cg.translateBy(x: slide, y: 0)
        fill(CGRect(x: 105, y: 232, width: 1070, height: 178), BATBrand.purple.withAlphaComponent(0.94), in: cg)
        fill(CGRect(x: 105, y: 232, width: 1070, height: 8), BATBrand.yellow, in: cg)
        fill(CGRect(x: 105, y: 402, width: 1070, height: 8), BATBrand.yellow, in: cg)
        cg.saveGState()
        cg.clip(to: CGRect(x: 105, y: 240, width: 1070, height: 162))
        let shift = CGFloat(now.truncatingRemainder(dividingBy: 2400) / 2400 * 160)
        cg.setFillColor(BATBrand.yellow.withAlphaComponent(0.42).cgColor)
        for x in stride(from: -190, through: 1390, by: 160) {
            let left = CGFloat(x) + shift
            let slash = UIBezierPath()
            slash.move(to: CGPoint(x: left, y: 402))
            slash.addLine(to: CGPoint(x: left + 34, y: 402))
            slash.addLine(to: CGPoint(x: left + 132, y: 240))
            slash.addLine(to: CGPoint(x: left + 98, y: 240))
            slash.close()
            cg.addPath(slash.cgPath)
            cg.fillPath()
        }
        cg.restoreGState()
        fill(CGRect(x: 337, y: 247, width: 606, height: 148), BATBrand.purple.withAlphaComponent(0.96), in: cg)
        label("FORZA BAT!", in: CGRect(x: 345, y: 250, width: 590, height: 109), size: 88, color: BATBrand.yellow)
        label("TUTTI INSIEME", in: CGRect(x: 405, y: 353, width: 470, height: 36), size: 26)
    }

    private func fill(_ rectangle: CGRect, _ color: UIColor, in cg: CGContext) {
        cg.setFillColor(color.cgColor)
        let path = UIBezierPath(roundedRect: rectangle, cornerRadius: rectangle.width < 12 ? 0 : 14)
        cg.addPath(path.cgPath)
        cg.fillPath()
    }

    private func color(_ hex: String) -> UIColor {
        let string = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard string.count == 6, let value = UInt64(string, radix: 16) else { return BATBrand.purple }
        return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                       green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255, alpha: 1)
    }

    private func drawLogo(_ value: String, in rectangle: CGRect) {
        guard let range = value.range(of: "base64,"),
              let data = Data(base64Encoded: String(value[range.upperBound...])),
              let image = UIImage(data: data) else { return }
        image.draw(in: rectangle)
    }

    private func label(_ title: String, in rectangle: CGRect, size: CGFloat, color: UIColor? = nil, alignment: NSTextAlignment = .center) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        let font = UIFont.systemFont(ofSize: size, weight: .heavy)
        let text = title as NSString
        text.draw(in: rectangle, withAttributes: [
            .font: font,
            .foregroundColor: color ?? ink,
            .paragraphStyle: style
        ])
    }
}
