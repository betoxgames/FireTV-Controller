import AppKit

let size = CGFloat(1024)
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

func rounded(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

let charcoal = NSColor(srgbRed: 0.055, green: 0.033, blue: 0.025, alpha: 1)
let dark = NSColor(srgbRed: 0.115, green: 0.068, blue: 0.041, alpha: 1)
let colors = [NSColor(srgbRed: 1, green: 0.81, blue: 0.27, alpha: 1), NSColor(srgbRed: 1, green: 0.65, blue: 0.16, alpha: 1), NSColor(srgbRed: 1, green: 0.48, blue: 0.10, alpha: 1), NSColor(srgbRed: 1, green: 0.32, blue: 0.035, alpha: 1), NSColor(srgbRed: 1, green: 0.68, blue: 0.39, alpha: 1)]
rounded(NSRect(x: 54, y: 54, width: 916, height: 916), radius: 210, color: charcoal)
let shell = NSBezierPath(roundedRect: NSRect(x: 216, y: 130, width: 592, height: 764), xRadius: 130, yRadius: 130)
dark.setFill(); shell.fill()
NSColor.white.withAlphaComponent(0.10).setStroke(); shell.lineWidth = 3; shell.stroke()
let center = NSPoint(x: 512, y: 610)
let radius: CGFloat = 214
for i in 0..<240 {
    let fraction = CGFloat(i) / 240 * CGFloat(colors.count)
    let index = Int(fraction)
    let color = colors[index].blended(withFraction: fraction - CGFloat(index), of: colors[(index+1) % colors.count]) ?? colors[index]
    let segment = NSBezierPath()
    segment.appendArc(withCenter: center, radius: radius, startAngle: CGFloat(i) * 1.5, endAngle: CGFloat(i + 1) * 1.5 + 0.4)
    segment.lineCapStyle = .round
    color.withAlphaComponent(0.08).setStroke(); segment.lineWidth = 46; segment.stroke()
    color.withAlphaComponent(0.24).setStroke(); segment.lineWidth = 25; segment.stroke()
    color.setStroke(); segment.lineWidth = 11; segment.stroke()
}
let inner = NSBezierPath(ovalIn: NSRect(x: 414, y: 512, width: 196, height: 196))
charcoal.setFill(); inner.fill(); colors[0].withAlphaComponent(0.65).setStroke(); inner.lineWidth = 6; inner.stroke()
for i in 0..<4 {
    let angle = CGFloat(i) * .pi / 2
    let dx = cos(angle), dy = sin(angle)
    let px = -dy, py = dx
    let tip = NSPoint(x: center.x + 180 * dx, y: center.y + 180 * dy)
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: tip.x - dx * 30 + px * 27, y: tip.y - dy * 30 + py * 27))
    arrow.line(to: tip)
    arrow.line(to: NSPoint(x: tip.x - dx * 30 - px * 27, y: tip.y - dy * 30 - py * 27))
    NSColor.white.withAlphaComponent(0.92).setStroke(); arrow.lineWidth = 12; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round; arrow.stroke()
}
for (i, color) in [colors[4], colors[1], colors[3]].enumerated() {
    let x = CGFloat(343 + i * 135)
    let circle = NSBezierPath(ovalIn: NSRect(x: x, y: 306, width: 68, height: 68))
    charcoal.setFill(); circle.fill(); color.setStroke(); circle.lineWidth = 5; circle.stroke()
}
rounded(NSRect(x: 362, y: 205, width: 300, height: 50), radius: 25, color: colors[0].withAlphaComponent(0.22))
image.unlockFocus()
if let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) {
    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
