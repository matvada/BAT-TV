import UIKit
import CoreText
import CoreImage

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
            if game.showScore {
                drawBroadcastScore(game, at: serverNow, in: cg)
            }
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

    private lazy var glassLogo: UIImage? = {
        guard let logo = channelLogo, let image = CIImage(image: logo),
              let filtered = CIContext().createCGImage(image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputBrightnessKey: 0.25, kCIInputContrastKey: 0.82]), from: image.extent) else { return channelLogo }
        return UIImage(cgImage: filtered)
    }()
    private func drawChannel(in cg: CGContext) {
        let rect = CGRect(x: 1089.28, y: 46.8, width: 67.84, height: 67.84)
        cg.saveGState(); UIBezierPath(roundedRect: rect, cornerRadius: 12.21).addClip()
        cg.setFillColor(UIColor.white.withAlphaComponent(0.052).cgColor); cg.fill(rect)
        glassLogo?.draw(in: rect, blendMode: .screen, alpha: 0.281)
        cg.restoreGState(); cg.setStrokeColor(UIColor.white.withAlphaComponent(0.15).cgColor); cg.setLineWidth(0.7)
        cg.addPath(UIBezierPath(roundedRect: rect, cornerRadius: 12.21).cgPath); cg.strokePath()
    }

    // Approved geometry uses a 320 × 118 design grid; scale the entire group together.
    private lazy var broadcastFont: String = {
        guard let url = Bundle.main.url(forResource: "Galiga", withExtension: "ttf", subdirectory: "BATWeb/broadcast"),
              let provider = CGDataProvider(url: url as CFURL), let font = CGFont(provider) else { return "HelveticaNeue-CondensedBlack" }
        CTFontManagerRegisterGraphicsFont(font, nil)
        return (font.postScriptName as String?) ?? "HelveticaNeue-CondensedBlack"
    }()
    private var crestCache: [String: UIImage] = [:]
    private lazy var broadcastBat: UIImage? = asset("watermark")
    private func asset(_ name: String) -> UIImage? {
        guard let path = Bundle.main.path(forResource: name, ofType: "png", inDirectory: "BATWeb/broadcast") else { return nil }
        return UIImage(contentsOfFile: path)
    }
    private func broadcastCrest(_ value: String) -> UIImage? {
        if let cached = crestCache[value] { return cached }
        let image: UIImage?
        if value.hasPrefix("preset:") { image = asset(String(value.dropFirst(7))) }
        else if let range = value.range(of: "base64,"), let data = Data(base64Encoded: String(value[range.upperBound...])) { image = UIImage(data: data) }
        else { image = nil }
        if let image { if crestCache.count > 24 { crestCache.removeAll() }; crestCache[value] = image }
        return image
    }
    private func panel(_ rect: CGRect, colors: [UIColor], locations: [CGFloat], in cg: CGContext, artwork: Bool = false) {
        cg.saveGState()
        cg.translateBy(x: rect.minX, y: rect.maxY)
        cg.concatenate(CGAffineTransform(a: 1, b: 0, c: -0.176327, d: 1, tx: 0, ty: 0))
        cg.translateBy(x: 0, y: -rect.height)
        cg.clip(to: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: locations) {
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: rect.height), options: [])
        }
        if artwork { broadcastBat?.draw(in: CGRect(x: rect.width * 0.1, y: -rect.height * 0.2, width: rect.width * 1.05, height: rect.height * 1.45), blendMode: .normal, alpha: 0.36) }
        if rect.height == 52 {
            let shine = UIBezierPath(); shine.move(to: CGPoint(x: 81, y: 0)); shine.addLine(to: CGPoint(x: 120, y: 0)); shine.addLine(to: CGPoint(x: 97, y: 52)); shine.addLine(to: CGPoint(x: 58, y: 52)); shine.close()
            cg.addPath(shine.cgPath); cg.setFillColor(UIColor.white.withAlphaComponent(0.07).cgColor); cg.fillPath()
        }
        cg.setFillColor(UIColor.white.withAlphaComponent(0.56).cgColor); cg.fill(CGRect(x: 0, y: 0, width: rect.width, height: 1))
        if rect.height == 52 { cg.setFillColor(UIColor.white.withAlphaComponent(0.44).cgColor); cg.fill(CGRect(x: 0, y: 50, width: rect.width, height: 2)) }
        cg.restoreGState()
    }
    private func mixed(_ base: UIColor, with other: UIColor, fraction: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        base.getRed(&r, green: &g, blue: &b, alpha: &a); other.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
        return UIColor(red: r * fraction + rr * (1-fraction), green: g * fraction + gg * (1-fraction), blue: b * fraction + bb * (1-fraction), alpha: 1)
    }
    private func broadcastText(_ text: String, in rect: CGRect, size: CGFloat, edge: NSTextAlignment, padding: CGFloat = 0, cg: CGContext) {
        guard !text.isEmpty else { return }
        func line(_ size: CGFloat) -> CTLine {
            let base = UIFont(name: broadcastFont, size: size) ?? UIFont.systemFont(ofSize: size)
            let font = UIFont(descriptor: base.fontDescriptor.withMatrix(CGAffineTransform(a: 1, b: 0, c: 0.176327, d: 1, tx: 0, ty: 0)), size: size)
            return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.white]))
        }
        var textLine = line(size)
        var bounds = CTLineGetBoundsWithOptions(textLine, .useGlyphPathBounds)
        let factor = min(1, (rect.width - 2 * padding) / max(1, bounds.width), (rect.height - 4) / max(1, bounds.height))
        if factor < 1 { textLine = line(size * factor); bounds = CTLineGetBoundsWithOptions(textLine, .useGlyphPathBounds) }
        let x = edge == .left ? padding - bounds.minX : edge == .right ? rect.width - padding - bounds.maxX : (rect.width - bounds.width) / 2 - bounds.minX
        cg.saveGState(); cg.translateBy(x: rect.minX, y: rect.maxY); cg.scaleBy(x: 1, y: -1)
        cg.textMatrix = .identity; cg.textPosition = CGPoint(x: x, y: (rect.height - bounds.height) / 2 - bounds.minY)
        CTLineDraw(textLine, cg); cg.restoreGState()
    }
    private func drawBroadcastScore(_ game: Game, at now: Double, in cg: CGContext) {
        cg.saveGState(); defer { cg.restoreGState() }
        let scale: CGFloat = 1280 * 0.205 / 320 * 0.9
        cg.translateBy(x: 1280 * 0.115, y: 720 * (1 - 0.043) - 118 * scale)
        cg.scaleBy(x: scale, y: scale)
        let left = game.homeOnLeft ? game.home : game.away
        let right = game.homeOnLeft ? game.away : game.home
        broadcastTeam(left, home: game.homeOnLeft, right: false, in: cg)
        cg.saveGState(); cg.translateBy(x: 155, y: 0)
        broadcastTeam(right, home: !game.homeOnLeft, right: true, in: cg); cg.restoreGState()
        panel(CGRect(x: -0.96, y: 87, width: 303, height: 30), colors: [UIColor(white: 0.3, alpha: 1), UIColor(red: 21/255, green: 24/255, blue: 25/255, alpha: 1), UIColor(red: 9/255, green: 11/255, blue: 13/255, alpha: 1)], locations: [0, 0.18, 1], in: cg)
        let quarter = game.quarter <= 4 ? ["PRIMO QUARTO", "SECONDO QUARTO", "TERZO QUARTO", "QUARTO QUARTO"][max(0, game.quarter - 1)] : "SUPPLEMENTARE \(game.quarter - 4)"
        // Counter-skewed ticker text: quarter stays left, clock stays right.
        broadcastText(quarter, in: CGRect(x: 14.489, y: 87, width: 180, height: 30), size: 15, edge: .left, cg: cg)
        if game.clockEnabled { broadcastText(game.clockText(at: now), in: CGRect(x: 221.895, y: 87, width: 70, height: 30), size: 19.2, edge: .right, cg: cg) }
    }
    private func broadcastTeam(_ team: Team, home: Bool, right: Bool, in cg: CGContext) {
        let base = color(team.color)
        panel(CGRect(x: 5, y: 12, width: 150, height: 52), colors: [mixed(base, with: .white, fraction: 0.76), base, mixed(base, with: UIColor(red: 5/255, green: 4/255, blue: 11/255, alpha: 1), fraction: 0.45)], locations: [0, 0.08, 1], in: cg, artwork: home)
        panel(CGRect(x: 1.44, y: 66, width: 150, height: 19), colors: [mixed(base, with: .white, fraction: 0.6), base, mixed(base, with: .black, fraction: 0.55)], locations: [0, 0.13, 1], in: cg)
        broadcastText("\(team.score)", in: CGRect(x: 9.584, y: 12, width: 150, height: 52), size: 41, edge: right ? .left : .right, padding: 12, cg: cg)
        broadcastText("F", in: CGRect(x: 12.706, y: 66, width: 10, height: 19), size: 11.84, edge: .center, cg: cg)
        broadcastText("TO", in: CGRect(x: 111.222, y: 66, width: 16, height: 19), size: 11.84, edge: .center, cg: cg)
        for (count, x, number) in [(team.fouls, CGFloat(26.222), 5), (team.timeouts, CGFloat(130.738), 3)] {
            for index in 0..<number {
                cg.saveGState(); cg.translateBy(x: x + CGFloat(index) * 4.96, y: 71.18); cg.concatenate(CGAffineTransform(a: 1, b: 0, c: -0.176327, d: 1, tx: 0, ty: 0))
                cg.setFillColor((index < count ? (home ? BATBrand.yellow : .white) : UIColor.white.withAlphaComponent(0.333)).cgColor)
                cg.fill(CGRect(x: 0, y: 0, width: 2.88, height: 8.64)); cg.restoreGState()
            }
        }
        let rect = CGRect(x: right ? 93.24 : 17.808, y: 0, width: 60.8, height: 60.8)
        cg.saveGState(); UIBezierPath(ovalIn: rect).addClip(); cg.setFillColor(UIColor.white.cgColor); cg.fill(rect)
        if let image = broadcastCrest(team.logo.isEmpty && home ? "preset:bat" : team.logo) { image.draw(in: rect) }
        else { broadcastText(String(team.name.prefix(3)).uppercased(), in: rect.insetBy(dx: 5, dy: 5), size: 16, edge: .center, cg: cg) }
        cg.restoreGState(); cg.setStrokeColor(UIColor.white.withAlphaComponent(0.5).cgColor); cg.setLineWidth(1); cg.strokeEllipse(in: rect.insetBy(dx: 0.5, dy: 0.5))
    }

    private func scoreLabel(_ title: String, x: CGFloat, width: CGFloat, centerY: CGFloat,
                            size: CGFloat, color: UIColor? = nil) {
        let height = UIFont.systemFont(ofSize: size, weight: .heavy).lineHeight
        label(title, in: CGRect(x: x, y: centerY - height / 2, width: width, height: height),
              size: size, color: color)
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

    private func color(_ hex: String, darkenedBy amount: CGFloat) -> UIColor {
        let value = color(hex)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard value.getRed(&r, green: &g, blue: &b, alpha: &a) else { return value }
        return UIColor(red: r * (1 - amount), green: g * (1 - amount), blue: b * (1 - amount), alpha: a)
    }

    private func drawLogo(_ value: String, in rectangle: CGRect) {
        guard let range = value.range(of: "base64,"),
              let data = Data(base64Encoded: String(value[range.upperBound...])),
              let image = UIImage(data: data) else { return }
        let scale = min(rectangle.width / image.size.width, rectangle.height / image.size.height)
        image.draw(in: CGRect(x: rectangle.midX - image.size.width * scale / 2,
                              y: rectangle.midY - image.size.height * scale / 2,
                              width: image.size.width * scale, height: image.size.height * scale))
    }

    private func label(_ title: String, in rectangle: CGRect, size: CGFloat, color: UIColor? = nil, alignment: NSTextAlignment = .center) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        let font = UIFont(name: broadcastFont, size: size) ?? UIFont.systemFont(ofSize: size, weight: .heavy)
        let text = title as NSString
        text.draw(in: rectangle, withAttributes: [
            .font: font,
            .obliqueness: 0.176327,
            .foregroundColor: color ?? ink,
            .paragraphStyle: style
        ])
    }
}
