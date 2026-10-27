import XCTest
@testable import VaultCore
final class CSVTests: XCTestCase {
    func testQuotedFieldsBOMAndNewlines() throws {
        let text = "\u{FEFF}name,username,password,notes\r\n\"Fictional, Mail\",reader@example.invalid,fictional-secret,\"line one\nline \"\"two\"\"\"\r\n"
        let table = try CSVTable(data: Data(text.utf8))
        let accounts = try CSVMapping(headers: table.headers).accounts(from: table)
        XCTAssertEqual(accounts.count, 1); XCTAssertEqual(accounts[0].name, "Fictional, Mail")
        XCTAssertEqual(accounts[0].notes, "line one\nline \"two\"")
    }
    func testValidation() throws {
        for text in ["name,password\n\"unterminated,x", "name,name\nx,y", "name,password\na,b,c", "name,password\n\"a\"bad,b"] {
            XCTAssertThrowsError(try CSVTable(data: Data(text.utf8)))
        }
        let table = try CSVTable(data: Data("name,password\nMail,\n".utf8))
        XCTAssertThrowsError(try CSVMapping(headers: table.headers).accounts(from: table))
        XCTAssertThrowsError(try CSVTable(data: Data(count: 8 * 1024 * 1024 + 1)))
        XCTAssertThrowsError(try CSVTable(data: Data([0xFF, 0xFE])))
    }
    func testDuplicateChoicesNeverOverwrite() throws {
        let table = try CSVTable(data: Data("name,username,password\nMail,reader,one\nMail,reader,two".utf8))
        let incoming = try CSVMapping(headers: table.headers).accounts(from: table)
        var existing = VaultPayload(); existing.accounts = [incoming[0]]
        XCTAssertEqual(ImportPlan.duplicateCount(incoming, existing: existing.accounts), 2)
        let skipped = try ImportPlan.apply(incoming, to: existing, keepDuplicates: false)
        XCTAssertEqual(skipped, existing)
        let kept = try ImportPlan.apply(incoming, to: existing, keepDuplicates: true)
        XCTAssertEqual(kept.accounts.count, 3); XCTAssertEqual(kept.accounts[0].password, "one")
        XCTAssertEqual(Set(kept.accounts.map(\.id)).count, 3)
    }
}
