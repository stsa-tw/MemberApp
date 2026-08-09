import CoreImage.CIFilterBuiltins
import SwiftUI

enum QRCode {
    /// Renders `string` as a QR code at `size` points.
    ///
    /// Correction level H to match the web card — the highest level, which keeps
    /// the code readable when a phone screen is scanned at an angle, behind a
    /// fingerprint, or at low brightness.
    static func image(for string: String, size: CGFloat, scale: CGFloat = 3) -> Image? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "H"

        guard let output = filter.outputImage else { return nil }

        // CIQRCodeGenerator emits one pixel per module; scale up with no
        // interpolation so the modules stay square-edged.
        let target = size * scale
        let factor = target / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: factor, y: factor))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }

        return Image(decorative: cgImage, scale: scale)
    }
}
