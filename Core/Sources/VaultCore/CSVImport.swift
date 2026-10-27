import Foundation

public struct CSVTable {
    public let headers: [String]
    public let rows: [[String]]
    public init(data: Data) throws {
        guard data.count <= 8 * 1024 * 1024 else { throw VaultError.tooLarge }
        guard var text = String(data: data, encoding: .utf8) else { throw VaultError.invalidFile }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        var records: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, closed = false, atStart = true
        let chars = Array(text); var i = 0
        func finishField() throws {
            guard field.utf8.count <= 65536, row.count < 64 else { throw VaultError.tooLarge }
            row.append(field); field = ""; atStart = true; closed = false
        }
        func finishRow() throws {
            try finishField()
            if row != [""] { records.append(row) }
            row = []
            guard records.count <= 10001 else { throw VaultError.tooLarge }
        }
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { quoted = false; closed = true }
                } else { field.append(c) }
            } else if c == "," { try finishField() }
            else if c == "\n" || c == "\r" || c == "\r\n" {
                try finishRow()
                if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
            } else if c == "\"" && atStart { quoted = true; atStart = false }
            else {
                guard !closed, c != "\"" else { throw VaultError.invalidFile }
                field.append(c); atStart = false
            }
            guard field.utf8.count <= 65536 else { throw VaultError.tooLarge }
            i += 1
        }
        guard !quoted else { throw VaultError.invalidFile }
        if !field.isEmpty || !row.isEmpty || closed { try finishRow() }
        guard let headers = records.first, !headers.isEmpty,
              headers.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1024 }),
              Set(headers).count == headers.count else { throw VaultError.invalidFile }
        let rows = Array(records.dropFirst())
        guard rows.allSatisfy({ $0.count == headers.count }) else { throw VaultError.invalidFile }
        self.headers = headers; self.rows = rows
    }
}
public struct CSVMapping {
    public var name: Int = 0
    public var website: Int = -1
    public var username: Int = -1
    public var password: Int = -1
    public var notes: Int = -1
    public init(headers: [String]) {
        func match(_ candidates: [String]) -> Int { headers.firstIndex { candidates.contains($0.lowercased().trimmingCharacters(in: .whitespaces)) } ?? -1 }
        name = match(["name", "title", "account"])
        website = match(["website", "url", "login_uri"])
        username = match(["username", "email", "login_username"])
        password = match(["password", "login_password"])
        notes = match(["notes", "note"])
    }
    public func accounts(from table: CSVTable) throws -> [Account] {
        let selected = [name, website, username, password, notes].filter { $0 >= 0 }
        guard name >= 0, password >= 0, Set(selected).count == selected.count,
              selected.allSatisfy({ $0 < table.headers.count }) else { throw VaultError.invalidEntry }
        return try table.rows.map { row in
            func value(_ index: Int) -> String { index >= 0 ? row[index] : "" }
            var account = Account(); account.name = value(name); account.website = value(website)
            account.username = value(username); account.password = value(password); account.notes = value(notes)
            try account.validate(); return account
        }
    }
}
public enum ImportPlan {
    public static func duplicateCount(_ incoming: [Account], existing: [Account]) -> Int {
        var seen = Set(existing.map(\.duplicateKey)); var count = 0
        for account in incoming { if !seen.insert(account.duplicateKey).inserted { count += 1 } }
        return count
    }
    public static func apply(_ incoming: [Account], to payload: VaultPayload, keepDuplicates: Bool) throws -> VaultPayload {
        var result = payload; var seen = Set(payload.accounts.map(\.duplicateKey))
        for var account in incoming {
            let isNew = seen.insert(account.duplicateKey).inserted
            if isNew || keepDuplicates { account.id = UUID(); result.accounts.append(account) }
        }
        try result.validate(); return result
    }
}
