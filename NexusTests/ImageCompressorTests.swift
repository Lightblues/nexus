import XCTest
@testable import Nexus

final class ImageCompressorTests: XCTestCase {
    private func pick(gif: Bool = false, alpha: Bool, original: Int = 1000, webp: Int?, jpeg: Int = 0) -> ImageCompressor.AutoPick {
        ImageCompressor.autoPick(isGIF: gif, hasAlpha: alpha, originalSize: original, webpSize: webp, jpegSize: jpeg)
    }

    func testGIFKeepsTheOriginal() {
        XCTAssertEqual(pick(gif: true, alpha: true, webp: 10), .original)
        XCTAssertEqual(pick(gif: true, alpha: false, webp: 10, jpeg: 10), .original)
    }

    func testAlphaPrefersWebPWhenSmallerThanTheOriginal() {
        XCTAssertEqual(pick(alpha: true, webp: 999), .webp)
        XCTAssertEqual(pick(alpha: true, webp: 1000), .png)
        XCTAssertEqual(pick(alpha: true, webp: 2000), .png)
    }

    func testAlphaWithoutWebPFallsBackToPNG() {
        XCTAssertEqual(pick(alpha: true, webp: nil), .png)
    }

    func testNoAlphaTakesTheSmallerOfJPEGAndWebP() {
        XCTAssertEqual(pick(alpha: false, webp: 400, jpeg: 500), .webp)
        XCTAssertEqual(pick(alpha: false, webp: 500, jpeg: 400), .jpeg)
        XCTAssertEqual(pick(alpha: false, webp: 500, jpeg: 500), .jpeg, "a tie keeps JPEG")
    }

    func testNoAlphaWithoutWebPTakesJPEG() {
        XCTAssertEqual(pick(alpha: false, webp: nil, jpeg: 5000), .jpeg, "even when larger than the original")
    }
}
