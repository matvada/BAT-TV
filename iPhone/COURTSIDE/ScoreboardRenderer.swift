import UIKit

@MainActor
final class ScoreboardRenderer {
    private let size = CGSize(width: 1280, height: 720)
    private let ink = UIColor.white

    func image(for game: Game, at serverNow: Double) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            if game.showScore { drawScore(game, at: serverNow, in: cg) }
            switch game.visibleOverlay(at: serverNow) {
            case "kiss": drawKiss(in: cg)
            case "triple":
                fill(CGRect(x: 292, y: 210, width: 696, height: 170), BATBrand.yellow.withAlphaComponent(0.96), in: cg)
                label("TRIPLA!", in: CGRect(x: 292, y: 210, width: 696, height: 170), size: 94, color: .black)
            case "break", "final":
                fill(CGRect(origin: .zero, size: size), BATBrand.purple.withAlphaComponent(0.88), in: cg)
                label(game.overlay == "final" ? "FINE PARTITA" : "INTERVALLO", in: CGRect(x: 80, y: 270, width: 1120, height: 120), size: 75)
                label("\(game.home.name)  \(game.home.score) – \(game.away.score)  \(game.away.name)", in: CGRect(x: 80, y: 395, width: 1120, height: 100), size: 40, color: BATBrand.yellow)
            case "caption":
                fill(CGRect(x: 58, y: 400, width: 1164, height: 90), BATBrand.purple.withAlphaComponent(0.96), in: cg)
                label(game.caption, in: CGRect(x: 86, y: 410, width: 1108, height: 70), size: 45, alignment: .left)
            default: break
            }
            drawChannel(in: cg)
        }
        return image.cgImage
    }

    private func drawChannel(in cg: CGContext) {
        UIImage(named: "BATLogo")?.draw(in: CGRect(x: 1162, y: 82, width: 80, height: 80))
    }

    private func drawScore(_ game: Game, at now: Double, in cg: CGContext) {
        cg.saveGState()
        cg.translateBy(x: 0, y: -70)
        defer { cg.restoreGState() }
        fill(CGRect(x: 58, y: 590, width: 1164, height: 84), BATBrand.purple.withAlphaComponent(0.96), in: cg)
        fill(CGRect(x: 58, y: 590, width: 7, height: 84), color(game.home.color), in: cg)
        fill(CGRect(x: 1215, y: 590, width: 7, height: 84), color(game.away.color), in: cg)
        drawLogo(game.home.logo, in: CGRect(x: 77, y: 600, width: 62, height: 62))
        drawLogo(game.away.logo, in: CGRect(x: 1141, y: 600, width: 62, height: 62))
        label(game.home.name.uppercased(), in: CGRect(x: 150, y: 603, width: 220, height: 57), size: 23, alignment: .left)
        label("\(game.home.score)", in: CGRect(x: 447, y: 603, width: 90, height: 57), size: 40)
        label("\(game.away.score)", in: CGRect(x: 743, y: 603, width: 90, height: 57), size: 40)
        label(game.away.name.uppercased(), in: CGRect(x: 899, y: 603, width: 230, height: 57), size: 23, alignment: .right)
        label(game.clockText(at: now), in: CGRect(x: 550, y: 597, width: 180, height: 40), size: 30, color: BATBrand.yellow)
        label(game.quarter <= 4 ? "Q\(game.quarter)" : "OT\(game.quarter - 4)", in: CGRect(x: 550, y: 636, width: 180, height: 26), size: 16, color: .lightGray)
    }

    private func drawKiss(in cg: CGContext) {
        cg.setStrokeColor(BATBrand.yellow.cgColor)
        cg.setLineWidth(16)
        let border = UIBezierPath(roundedRect: CGRect(x: 30, y: 80, width: 1220, height: 560), cornerRadius: 32)
        cg.addPath(border.cgPath)
        cg.strokePath()
        fill(CGRect(x: 385, y: 80, width: 510, height: 95), BATBrand.purple, in: cg)
        label("KISS CAM", in: CGRect(x: 405, y: 80, width: 470, height: 95), size: 65)
        label("♥", in: CGRect(x: 80, y: 150, width: 120, height: 110), size: 100, color: BATBrand.yellow)
        label("♥", in: CGRect(x: 1080, y: 150, width: 120, height: 110), size: 100, color: BATBrand.yellow)
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
