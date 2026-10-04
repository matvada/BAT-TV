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
        let rect = CGRect(x: 1132, y: 72, width: 110, height: 110)
        cg.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: 18).addClip()
        cg.interpolationQuality = .high
        channelLogo?.draw(in: rect)
        cg.restoreGState()
    }

    private func drawScore(_ game: Game, at now: Double, in cg: CGContext) {
        fill(CGRect(x: 58, y: 590, width: 1164, height: 84), BATBrand.purple.withAlphaComponent(0.96), in: cg)
        fill(CGRect(x: 58, y: 590, width: 7, height: 84), color(game.home.color), in: cg)
        fill(CGRect(x: 1215, y: 590, width: 7, height: 84), color(game.away.color), in: cg)
        drawLogo(game.home.logo, in: CGRect(x: 77, y: 600, width: 62, height: 62))
        drawLogo(game.away.logo, in: CGRect(x: 1141, y: 600, width: 62, height: 62))
        label(game.home.name.uppercased(), in: CGRect(x: 150, y: 603, width: 220, height: 57), size: 23, alignment: .left)
        label("\(game.home.score)", in: CGRect(x: 447, y: 603, width: 90, height: 57), size: 40)
        label("\(game.away.score)", in: CGRect(x: 743, y: 603, width: 90, height: 57), size: 40)
        label(game.away.name.uppercased(), in: CGRect(x: 899, y: 603, width: 230, height: 57), size: 23, alignment: .right)
        let quarter = game.quarter <= 4 ? "Q\(game.quarter)" : "OT\(game.quarter - 4)"
        if game.clockEnabled {
            label(game.clockText(at: now), in: CGRect(x: 550, y: 597, width: 180, height: 40), size: 30, color: BATBrand.yellow)
            label(quarter, in: CGRect(x: 550, y: 636, width: 180, height: 26), size: 16, color: .lightGray)
        } else {
            label(quarter, in: CGRect(x: 530, y: 591, width: 220, height: 80), size: 56, color: BATBrand.yellow)
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
