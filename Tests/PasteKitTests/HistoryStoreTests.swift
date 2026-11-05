import Foundation
import XCTest

@testable import PasteKit

/// Unit tests for the persisted clipboard history.
///
/// Every store is created with an explicit temporary directory. Nothing here may touch
/// `~/Library/Application Support/Paste`; `HistoryStore` accepts a directory for exactly this
/// reason.
final class HistoryStoreTests: XCTestCase {

    // MARK: - Helpers

    /// Whole-second dates keep `JSONEncoder`/`JSONDecoder` `.iso8601` round-trips exact.
    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + seconds)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func textPayload(_ text: String, sourceApp: String? = nil) -> ClipboardPayload {
        ClipboardPayload(
            kind: .text,
            text: text,
            sourceApp: sourceApp,
            byteCount: text.utf8.count
        )
    }

    private func imagePayload(_ data: Data, width: Int, height: Int) -> ClipboardPayload {
        ClipboardPayload(
            kind: .image,
            imageData: data,
            pixelWidth: width,
            pixelHeight: height,
            byteCount: data.count
        )
    }

    private func makeImageData() -> Data {
        // A tiny deterministic payload. HistoryStore stores the bytes verbatim, so a real PNG is
        // not required to exercise image file storage and retrieval.
        Data((0 ..< 64).map { UInt8($0) })
    }

    // MARK: - Ordering

    @MainActor
    func testAddsKeepNewestFirstOrdering() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = HistoryStore(directory: directory, maxItems: 100, load: false)
        XCTAssertEqual(store.items, [], "A store with load: false starts empty")
        XCTAssertEqual(store.directory.standardizedFileURL, directory.standardizedFileURL)

        // Deliberately insert out of chronological order.
        store.add(textPayload("second"), at: date(20))
        store.add(textPayload("oldest"), at: date(10))
        store.add(textPayload("newest"), at: date(30))

        XCTAssertEqual(store.items.count, 3)
        XCTAssertEqual(store.items.map(\.text), ["newest", "second", "oldest"])
        XCTAssertEqual(
            store.items.map(\.createdAt),
            [date(30), date(20), date(10)],
            "Items are always sorted newest first"
        )
    }

    // MARK: - Duplicates

    @MainActor
    func testDuplicateCopyUpdatesDateMovesToTopAndKeepsPin() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = HistoryStore(directory: directory, maxItems: 100, load: false)
        store.add(textPayload("alpha", sourceApp: "Notes"), at: date(10))
        store.add(textPayload("beta"), at: date(20))

        let alpha = try XCTUnwrap(store.items.first { $0.text == "alpha" })
        store.togglePin(alpha.id)
        XCTAssertTrue(try XCTUnwrap(store.item(withID: alpha.id)).isPinned)

        // Copy the same text again: it must not duplicate, must get a fresh timestamp, and must
        // keep its identity and pin state.
        store.add(textPayload("alpha", sourceApp: "Safari"), at: date(30))

        XCTAssertEqual(store.items.count, 2, "Duplicate content must not create a second row")
        XCTAssertEqual(store.items.first?.id, alpha.id)
        XCTAssertEqual(store.items.map(\.text), ["alpha", "beta"])

        let refreshed = try XCTUnwrap(store.item(withID: alpha.id))
        XCTAssertEqual(refreshed.createdAt, date(30), "Re-copy refreshes the timestamp")
        XCTAssertTrue(refreshed.isPinned, "Re-copy preserves the pin state")
        XCTAssertEqual(refreshed.sourceApp, "Safari", "Re-copy refreshes the source app")
        XCTAssertEqual(refreshed.contentHash, ClipboardItem.hash(text: "alpha"))
    }

    // MARK: - Deletion

    @MainActor
    func testBatchDeleteRemovesOnlyRequestedIDs() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = HistoryStore(directory: directory, maxItems: 100, load: false)
        for (index, text) in ["a", "b", "c", "d"].enumerated() {
            store.add(textPayload(text), at: date(TimeInterval(index)))
        }
        XCTAssertEqual(store.items.count, 4)

        let doomed = Set(store.items.filter { $0.text == "b" || $0.text == "d" }.map(\.id))
        XCTAssertEqual(doomed.count, 2)
        store.delete(ids: doomed)

        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(Set(store.items.map(\.text)), ["a", "c"])
        XCTAssertTrue(store.items.allSatisfy { !doomed.contains($0.id) })

        // Deleting a missing id is a no-op rather than a crash.
        store.delete(ids: [UUID()])
        XCTAssertEqual(store.items.count, 2)
    }

    @MainActor
    func testDeletingImageItemRemovesStoredFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = HistoryStore(directory: directory, maxItems: 100, load: false)
        let data = makeImageData()
        let image = try XCTUnwrap(store.add(imagePayload(data, width: 4, height: 4)))

        let fileName = try XCTUnwrap(image.imageFile)
        let imageURL = directory.appendingPathComponent("Images", isDirectory: true)
            .appendingPathComponent(fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))
        XCTAssertEqual(store.imageData(for: image), data)

        store.delete(image.id)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: imageURL.path),
            "Deleting an image item also removes its file from the Images directory"
        )
    }

    // MARK: - clearUnpinned / pinning

    @MainActor
    func testClearUnpinnedKeepsPinnedItemsOnly() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = HistoryStore(directory: directory, maxItems: 100, load: false)
        store.add(textPayload("old"), at: date(10))
        store.add(textPayload("pinned"), at: date(20))
        store.add(textPayload("new"), at: date(30))

        let pinned = try XCTUnwrap(store.items.first { $0.text == "pinned" })
        store.togglePin(pinned.id)

        store.clearUnpinned()

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.id, pinned.id)
        XCTAssertTrue(try XCTUnwrap(store.items.first).isPinned)
    }

    @MainActor
    func testClearUnpinnedKeepsPinnedImageFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = HistoryStore(directory: directory, maxItems: 100, load: false)
        let pinnedImage = try XCTUnwrap(store.add(imagePayload(makeImageData(), width: 8, height: 8), at: date(10)))
        store.add(textPayload("transient"), at: date(20))
        store.togglePin(pinnedImage.id)

        store.clearUnpinned()

        let fileName = try XCTUnwrap(pinnedImage.imageFile)
        let imageURL = directory.appendingPathComponent("Images", isDirectory: true)
            .appendingPathComponent(fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))
        XCTAssertEqual(store.items.map(\.id), [pinnedImage.id])
    }

    @MainActor
    func testTogglePinFlipsStateBothWays() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = HistoryStore(directory: directory, maxItems: 100, load: false)
        let item = try XCTUnwrap(store.add(textPayload("pin me"), at: date(10)))
        XCTAssertFalse(item.isPinned)

        store.togglePin(item.id)
        XCTAssertTrue(try XCTUnwrap(store.item(withID: item.id)).isPinned)

        store.togglePin(item.id)
        XCTAssertFalse(try XCTUnwrap(store.item(withID: item.id)).isPinned)

        // Toggling an unknown id is a harmless no-op.
        store.togglePin(UUID())
        XCTAssertEqual(store.items.count, 1)
    }

    // MARK: - Pruning

    @MainActor
    func testMaxItemsPrunesOldestUnpinnedItem() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = HistoryStore(directory: directory, maxItems: 3, load: false)
        store.add(textPayload("t1"), at: date(10))
        store.add(textPayload("t2"), at: date(20))
        store.add(textPayload("t3"), at: date(30))
        store.add(textPayload("t4"), at: date(40))

        XCTAssertEqual(store.items.count, 3, "maxItems caps the rolling history")
        XCTAssertEqual(store.items.map(\.text), ["t4", "t3", "t2"])
        XCTAssertFalse(store.items.contains { $0.text == "t1" }, "The oldest unpinned item is pruned")
    }

    @MainActor
    func testMaxItemsNeverPrunesPinnedItems() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = HistoryStore(directory: directory, maxItems: 3, load: false)
        let pinned = try XCTUnwrap(store.add(textPayload("pinned"), at: date(10)))
        store.togglePin(pinned.id)
        store.add(textPayload("t2"), at: date(20))
        store.add(textPayload("t3"), at: date(30))
        store.add(textPayload("t4"), at: date(40))

        XCTAssertEqual(store.items.count, 3)
        XCTAssertTrue(store.items.contains { $0.id == pinned.id }, "Pinned items survive pruning")
        XCTAssertFalse(store.items.contains { $0.text == "t2" }, "The oldest unpinned item is pruned")

        // With a pinned item the next insert must prune another unpinned item, still keeping the pin.
        store.add(textPayload("t5"), at: date(50))
        XCTAssertEqual(store.items.count, 3)
        XCTAssertTrue(store.items.contains { $0.id == pinned.id })
        XCTAssertEqual(store.items.map(\.text), ["t5", "t4", "pinned"])
    }

    // MARK: - Persistence

    @MainActor
    func testPersistenceRoundTripIncludingImageFileAndData() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageData = makeImageData()
        let firstStore = HistoryStore(directory: directory, maxItems: 100, load: false)
        let text = try XCTUnwrap(
            firstStore.add(
                ClipboardPayload(
                    kind: .text,
                    text: "round trip",
                    rtfData: Data("rtf".utf8),
                    htmlData: Data("<b>html</b>".utf8),
                    sourceApp: "Tests",
                    byteCount: 10
                ),
                at: date(10)
            )
        )
        let image = try XCTUnwrap(
            firstStore.add(imagePayload(imageData, width: 4, height: 4), at: date(20))
        )

        let historyURL = directory.appendingPathComponent("history.json")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: historyURL.path),
            "Mutations persist history.json inside the injected directory"
        )

        // Reload from disk in a fresh store.
        let secondStore = HistoryStore(directory: directory, maxItems: 100)
        XCTAssertEqual(secondStore.items.count, 2)
        XCTAssertEqual(secondStore.items.map(\.id), [image.id, text.id], "Order survives reload")
        XCTAssertEqual(secondStore.items.map(\.kind), [.image, .text])

        let restoredText = try XCTUnwrap(secondStore.item(withID: text.id))
        XCTAssertEqual(restoredText.text, "round trip")
        XCTAssertEqual(restoredText.sourceApp, "Tests")
        XCTAssertEqual(restoredText.byteCount, 10)
        XCTAssertEqual(restoredText.contentHash, ClipboardItem.hash(text: "round trip"))
        XCTAssertEqual(restoredText.rtfData, Data("rtf".utf8))
        XCTAssertEqual(restoredText.htmlData, Data("<b>html</b>".utf8))
        XCTAssertEqual(restoredText.createdAt.timeIntervalSince1970,
                       text.createdAt.timeIntervalSince1970,
                       accuracy: 0.001)
        XCTAssertFalse(restoredText.isPinned)

        let restoredImage = try XCTUnwrap(secondStore.item(withID: image.id))
        XCTAssertEqual(restoredImage.kind, .image)
        XCTAssertEqual(restoredImage.pixelWidth, 4)
        XCTAssertEqual(restoredImage.pixelHeight, 4)
        let imageFile = try XCTUnwrap(restoredImage.imageFile)
        XCTAssertEqual(imageFile, "\(restoredImage.id.uuidString).png")

        let imageURL = directory.appendingPathComponent("Images", isDirectory: true)
            .appendingPathComponent(imageFile)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: imageURL.path),
            "Image bytes live in Images/<id>.png next to history.json"
        )
        XCTAssertEqual(try Data(contentsOf: imageURL), imageData)
        XCTAssertEqual(secondStore.imageData(for: restoredImage), imageData,
                       "Image data is readable back after a reload")
    }

    @MainActor
    func testPinnedStateAndSourceSurviveReload() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstStore = HistoryStore(directory: directory, maxItems: 100, load: false)
        let item = try XCTUnwrap(firstStore.add(textPayload("keep", sourceApp: "Terminal"), at: date(10)))
        firstStore.togglePin(item.id)

        let secondStore = HistoryStore(directory: directory, maxItems: 100)
        let restored = try XCTUnwrap(secondStore.item(withID: item.id))
        XCTAssertTrue(restored.isPinned)
        XCTAssertEqual(restored.sourceApp, "Terminal")
    }

    @MainActor
    func testLoadingLegacyBareArrayAndToleratingMissingFields() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Older builds wrote a bare `[ClipboardItem]` array; new optional fields may be missing.
        let legacyJSON = """
        [
          {
            "kind": "text",
            "text": "legacy",
            "createdAt": "2024-01-02T03:04:05Z",
            "isPinned": true
          },
          {
            "kind": "text",
            "text": "older",
            "createdAt": "2024-01-01T00:00:00Z"
          }
        ]
        """
        try Data(legacyJSON.utf8).write(to: directory.appendingPathComponent("history.json"))

        let store = HistoryStore(directory: directory, maxItems: 100)

        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.map(\.text), ["legacy", "older"])
        XCTAssertTrue(try XCTUnwrap(store.items.first).isPinned)
        XCTAssertFalse(try XCTUnwrap(store.items.last).isPinned, "Missing isPinned defaults to false")
        XCTAssertFalse(store.items.contains { $0.kind != .text })
    }

    // MARK: - updateText

    @MainActor
    func testUpdateTextReplacesBodyAndDropsRichData() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = HistoryStore(directory: directory, maxItems: 100, load: false)
        let item = try XCTUnwrap(
            store.add(
                ClipboardPayload(
                    kind: .text,
                    text: "draft",
                    rtfData: Data("rtf".utf8),
                    htmlData: Data("<i>draft</i>".utf8),
                    byteCount: 5
                ),
                at: date(10)
            )
        )

        let edited = "edited body"
        XCTAssertTrue(store.updateText(item.id, text: edited))

        let updated = try XCTUnwrap(store.item(withID: item.id))
        XCTAssertEqual(updated.text, edited)
        XCTAssertEqual(updated.contentHash, ClipboardItem.hash(text: edited))
        XCTAssertEqual(updated.byteCount, edited.utf8.count)
        XCTAssertNil(updated.rtfData, "Editing plain text drops the stale rich representation")
        XCTAssertNil(updated.htmlData)
        XCTAssertEqual(updated.createdAt, item.createdAt, "Editing does not change the timestamp")
    }

    @MainActor
    func testUpdateTextRejectsBlankTextAndNonTextItems() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = HistoryStore(directory: directory, maxItems: 100, load: false)
        let textItem = try XCTUnwrap(store.add(textPayload("body"), at: date(10)))
        let imageItem = try XCTUnwrap(store.add(imagePayload(makeImageData(), width: 2, height: 2), at: date(20)))

        XCTAssertFalse(store.updateText(textItem.id, text: "   \n  "), "Blank text is rejected")
        XCTAssertEqual(store.item(withID: textItem.id)?.text, "body")

        XCTAssertFalse(store.updateText(imageItem.id, text: "not allowed"), "Only text items are editable")
        XCTAssertNil(store.item(withID: imageItem.id)?.text)

        XCTAssertFalse(store.updateText(UUID(), text: "ghost"), "Unknown ids are rejected")
    }

    @MainActor
    func testUpdateTextMergesIntoAnExistingDuplicate() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = HistoryStore(directory: directory, maxItems: 100, load: false)
        let first = try XCTUnwrap(store.add(textPayload("first"), at: date(10)))
        let second = try XCTUnwrap(store.add(textPayload("second"), at: date(20)))
        XCTAssertEqual(store.items.count, 2)

        // Editing "second" to "first" would duplicate content, so the older duplicate is removed.
        XCTAssertTrue(store.updateText(second.id, text: "first"))

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.id, second.id)
        XCTAssertEqual(store.items.first?.text, "first")
        XCTAssertNil(store.item(withID: first.id))
    }
}
