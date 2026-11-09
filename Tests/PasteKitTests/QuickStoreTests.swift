import Foundation
import XCTest

@testable import PasteKit

final class QuickStoreTests: XCTestCase {
    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteQuickTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    func testFoldersAndSnippetsPersist() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = QuickStore(directory: directory)
        let folder = try XCTUnwrap(store.addFolder(named: "开发"))
        XCTAssertNil(store.addFolder(named: "开发"), "duplicate folder names are rejected")

        let snippet = try XCTUnwrap(
            store.addSnippet(folderID: folder.id, content: "print(1)", note: "调试")
        )
        XCTAssertEqual(store.folders.map(\.name), ["开发"])
        XCTAssertEqual(store.snippets.map(\.id), [snippet.id])

        let reloaded = QuickStore(directory: directory)
        XCTAssertEqual(reloaded.folders.map(\.name), ["开发"])
        XCTAssertEqual(reloaded.snippets.first?.content, "print(1)")
        XCTAssertEqual(reloaded.snippets.first?.note, "调试")
        XCTAssertEqual(reloaded.snippets.first?.folderID, folder.id)
    }

    @MainActor
    func testEditingAndDeletingSnippet() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = QuickStore(directory: directory)
        let folder = try XCTUnwrap(store.addFolder(named: "回复"))
        let snippet = try XCTUnwrap(
            store.addSnippet(folderID: nil, content: "旧内容", note: "")
        )
        XCTAssertNotNil(store.updateSnippet(id: snippet.id, folderID: folder.id, content: "新内容", note: "备注"))
        XCTAssertEqual(store.snippets.first?.content, "新内容")
        XCTAssertEqual(store.snippets.first?.folderID, folder.id)

        store.deleteSnippet(id: snippet.id)
        XCTAssertTrue(store.snippets.isEmpty)
    }

    @MainActor
    func testDeletingFolderMovesSnippetsToUncategorized() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = QuickStore(directory: directory)
        let folder = try XCTUnwrap(store.addFolder(named: "临时"))
        _ = try XCTUnwrap(store.addSnippet(folderID: folder.id, content: "内容", note: ""))

        store.deleteFolder(id: folder.id)
        XCTAssertTrue(store.folders.isEmpty)
        XCTAssertNil(store.snippets.first?.folderID)
    }

    @MainActor
    func testEmptySnippetContentIsRejected() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = QuickStore(directory: directory)
        XCTAssertNil(store.addSnippet(folderID: nil, content: "   \n", note: "备注"))
        XCTAssertTrue(store.snippets.isEmpty)
    }
}
