import Charts
import SwiftUI

/// Gráfica de la curva del cursor: velocidad del cursor según la aceleración del dedo.
/// Ambos ejes empiezan en 0 y se redibuja al mover los deslizadores. Usa la misma función
/// que el teclado, así que muestra exactamente lo que hace el cursor.
struct CursorCurveChart: View {
    let settings: KeyboardSettings

    /// Margen por encima y a la derecha del punto de velocidad máxima, para verlo completo.
    private static let xHeadroom = 1.5
    private static let yHeadroom = 1.2
    private static let sampleCount = 60

    private var points: [CurvePoint] {
        let maxFingerSpeed = settings.cursorMaxAcceleration * Self.xHeadroom
        return (0...Self.sampleCount).map { index in
            let fingerSpeed = maxFingerSpeed * Double(index) / Double(Self.sampleCount)
            return CurvePoint(
                fingerSpeed: fingerSpeed,
                cursorSpeed: settings.cursorSpeed(forFingerSpeed: fingerSpeed)
            )
        }
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Aceleración del dedo", point.fingerSpeed),
                    y: .value("Velocidad del cursor", point.cursorSpeed)
                )
            }
            PointMark(
                x: .value("Aceleración máxima", settings.cursorMaxAcceleration),
                y: .value("Velocidad máxima", settings.cursorMaxSpeed)
            )
        }
        .chartXScale(domain: 0...max(settings.cursorMaxAcceleration * Self.xHeadroom, 1))
        .chartYScale(domain: 0...max(settings.cursorMaxSpeed * Self.yHeadroom, 1))
        .chartXAxisLabel("Aceleración del dedo (pt/s)")
        .chartYAxisLabel("Velocidad del cursor (car/s)")
        .frame(height: 170)
        .padding(.vertical, 4)
        .accessibilityLabel("Gráfica de la curva del cursor")
    }
}

private struct CurvePoint: Identifiable {
    let fingerSpeed: Double
    let cursorSpeed: Double

    var id: Double { fingerSpeed }
}
