import SwiftUI

/// La firma grafica dell'app: una linea a zig-zag (la scintilla, il tratto
/// di circuito). È una `Shape` pura: statica di suo, quindi intrinsecamente
/// rispettosa di Reduce Motion; eventuali animazioni le decide chi la usa,
/// attraverso i token di `MotionTokens` (mai pulsazioni o lampeggi).
public struct ZigZagShape: Shape {
    /// Numero di "denti" della linea.
    public var segments: Int
    /// Ampiezza verticale dei denti, in punti.
    public var amplitude: CGFloat

    public init(segments: Int = 6, amplitude: CGFloat = 8) {
        self.segments = max(1, segments)
        self.amplitude = amplitude
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = rect.width / CGFloat(segments)
        let midY = rect.midY
        path.move(to: CGPoint(x: rect.minX, y: midY))
        for index in 0..<segments {
            let x = rect.minX + step * (CGFloat(index) + 0.5)
            let y = index.isMultiple(of: 2) ? midY - amplitude : midY + amplitude
            path.addLine(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: rect.minX + step * CGFloat(index + 1), y: midY))
        }
        return path
    }
}
