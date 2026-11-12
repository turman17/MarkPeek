import XCTest

final class ImageEmbedderTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ImageEmbedderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("images"), withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: folder.appendingPathComponent("images/a.png"))
        try Data("secret".utf8).write(to: folder.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).txt"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testEmbedsFilesInsideTheFolder() {
        let resolve = ImageEmbedder.resolver(folder: folder, containedOnly: true)
        XCTAssertEqual(resolve("images/a.png")?.hasPrefix("data:image/png;base64,"), true)
        XCTAssertNil(resolve("https://example.com/a.png"))
        XCTAssertNil(resolve("data:image/png;base64,AA=="))
    }

    func testContainedModeRefusesEscapes() throws {
        let outside = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath: folder.deletingLastPathComponent().path)
            .first { $0.hasPrefix("outside-") })
        let resolve = ImageEmbedder.resolver(folder: folder, containedOnly: true)
        XCTAssertNil(resolve("../\(outside)"))
        XCTAssertNil(resolve("file://" + folder.deletingLastPathComponent().appendingPathComponent(outside).path))
        let open = ImageEmbedder.resolver(folder: folder)
        XCTAssertNotNil(open("../\(outside)"), "the app's resolver may follow relative paths into allowed folders")
    }
}
