import XCTest
@testable import DocumentKit

@MainActor
final class CloudDocumentsTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/prueba", isDirectory: true)

    func testDriveURLUsesUserHomeNotSandboxContainer() {
        XCTAssertEqual(CloudDocuments.driveURL(home: home).path, "/Users/prueba/Library/Mobile Documents/com~apple~CloudDocs")
    }

    func testAcceptsDriveRootAndSubfolders() {
        let drive = CloudDocuments.driveURL(home: home)
        XCTAssertTrue(CloudDocuments.isInsideDrive(drive, home: home))
        XCTAssertTrue(CloudDocuments.isInsideDrive(drive.appendingPathComponent("EditorFinal", isDirectory: true), home: home))
    }

    func testRejectsFoldersOutsideDrive() {
        XCTAssertFalse(CloudDocuments.isInsideDrive(URL(fileURLWithPath: "/Users/prueba/Documents"), home: home))
        XCTAssertFalse(CloudDocuments.isInsideDrive(URL(fileURLWithPath: "/Users/prueba/Library/Mobile Documents/com~apple~CloudDocsFalso"), home: home))
        XCTAssertFalse(CloudDocuments.isInsideDrive(URL(fileURLWithPath: "/Users/prueba/Library/Mobile Documents/com~apple~CloudDocs/../../Documents"), home: home))
    }

    func testRememberRejectsFolderOutsideDrive() {
        XCTAssertThrowsError(try CloudDocuments.remember(FileManager.default.temporaryDirectory))
    }
}
