import Foundation
import XCTest

@testable import PasteKit

/// Coverage for the pure model helpers used by search, hashing and presentation.
final class ClipboardItemTests: XCTestCase {

    private func textItem(
        _ text: String,
        sourceApp: String? = nil,
        isPinned: Bool = false
    ) -> ClipboardItem {
        ClipboardItem(
            kind: .text,
            text: text,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            isPinned: isPinned,
            sourceApp: sourceApp,
            contentHash: ClipboardItem.hash(text: text),
            byteCount: text.utf8.count
        )
    }

    // MARK: - matches

    func testEmptyOrWhitespaceQueryMatchesEverything() {
        let item = textItem("hello")
        XCTAssertTrue(item.matches(""))
        XCTAssertTrue(item.matches("   "))
        XCTAssertTrue(item.matches("\n\t"))
    }

    func testTextItemMatchesSubstringCaseInsensitively() {
        let item = textItem("Hello SwiftUI World")
        XCTAssertTrue(item.matches("swiftui"))
        XCTAssertTrue(item.matches("HELLO"))
        XCTAssertTrue(item.matches("  swiftui world  "), "Query is trimmed before matching")
        XCTAssertTrue(item.matches("hello swiftui world"))
        XCTAssertFalse(item.matches("appkit"))
    }

    func testTextItemMatchesSourceAppAndKindLabel() {
        let item = textItem("console.log(1)", sourceApp: "Visual Studio Code")
        XCTAssertTrue(item.matches("visual studio"))
        XCTAssertTrue(item.matches("code"))
        XCTAssertTrue(item.matches("文本"), "Kind label is searchable")
    }

    func testImageItemMatchesKindLabelAndPixelDimensions() {
        let item = ClipboardItem(
            kind: .image,
            imageFile: "shot.png",
            pixelWidth: 1920,
            pixelHeight: 1080,
            contentHash: ClipboardItem.hash(imageData: Data([1, 2, 3])),
            byteCount: 3
        )
        XCTAssertTrue(item.matches("图片"))
        XCTAssertTrue(item.matches("1920"))
        XCTAssertTrue(item.matches("1920x1080"))
        XCTAssertTrue(item.matches("1920×1080"), "Both multiplication signs are searchable")
        XCTAssertFalse(item.matches("文本"))
        XCTAssertFalse(item.matches("png"), "The internal image file name is not part of search")
    }

    func testFilesItemMatchesFullPathAndFileName() {
        let item = ClipboardItem(
            kind: .files,
            filePaths: ["/Users/edy/Documents/Design Spec.pdf", "/tmp/notes.txt"],
            contentHash: ClipboardItem.hash(filePaths: ["/Users/edy/Documents/Design Spec.pdf", "/tmp/notes.txt"])
        )
        XCTAssertTrue(item.matches("design spec"))
        XCTAssertTrue(item.matches("Design"))
        XCTAssertTrue(item.matches("notes.txt"))
        XCTAssertTrue(item.matches("/tmp/notes"))
        XCTAssertTrue(item.matches("文件"))
        XCTAssertFalse(item.matches("spreadsheet"))
    }

    // MARK: - Hashing

    func testHashesAreStableAndKindScoped() {
        XCTAssertEqual(ClipboardItem.hash(text: "same"), ClipboardItem.hash(text: "same"))
        XCTAssertNotEqual(ClipboardItem.hash(text: "same"), ClipboardItem.hash(text: "other"))

        // Same bytes hashed as text vs image must not collide because the digest is prefixed.
        let bytes = Data("payload".utf8)
        XCTAssertNotEqual(ClipboardItem.hash(text: "payload"), ClipboardItem.hash(imageData: bytes))
        XCTAssertEqual(ClipboardItem.hash(imageData: bytes), ClipboardItem.hash(imageData: bytes))

        XCTAssertEqual(
            ClipboardItem.hash(filePaths: ["/a", "/b"]),
            ClipboardItem.hash(filePaths: ["/a", "/b"])
        )
        XCTAssertNotEqual(
            ClipboardItem.hash(filePaths: ["/a", "/b"]),
            ClipboardItem.hash(filePaths: ["/ab"])
        )
        XCTAssertNotEqual(
            ClipboardItem.hash(filePaths: ["/a", "/b"]),
            ClipboardItem.hash(filePaths: ["/b", "/a"]),
            "Order is part of a file list identity"
        )
    }

    func testPayloadContentHashUsesKindSpecificDigest() {
        let textPayload = ClipboardPayload(kind: .text, text: "clip")
        XCTAssertEqual(textPayload.contentHash, ClipboardItem.hash(text: "clip"))

        let imageData = Data([1, 2, 3, 4])
        let imagePayload = ClipboardPayload(kind: .image, imageData: imageData)
        XCTAssertEqual(imagePayload.contentHash, ClipboardItem.hash(imageData: imageData))

        let filesPayload = ClipboardPayload(kind: .files, filePaths: ["/one", "/two"])
        XCTAssertEqual(filesPayload.contentHash, ClipboardItem.hash(filePaths: ["/one", "/two"]))
    }
}
