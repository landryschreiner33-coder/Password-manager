import Foundation
import CryptoKit
import Darwin

public struct VaultFile {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func read() throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw VaultError.storage }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size >= 0, info.st_size <= Limits.fileBytes else { throw VaultError.tooLarge }
        var result = Data(); var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            guard count >= 0 else { throw VaultError.storage }
            if count == 0 { break }
            guard result.count + count <= Limits.fileBytes else { throw VaultError.tooLarge }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }
    public static func digest(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }
    /// expected=nil requires a new destination; never silently clobbers an existing file.
    public func write(_ data: Data, expected: Data?, beforeCommit: () throws -> Void = {}) throws {
        guard data.count <= Limits.fileBytes else { throw VaultError.tooLarge }
        let parent = url.deletingLastPathComponent()
        let temporary = parent.appendingPathComponent(".stillwater-\(UUID().uuidString).tmp")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw VaultError.storage }
        defer { close(fd); unlink(temporary.path) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let n = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                guard n > 0 else { throw VaultError.storage }; offset += n
            }
        }
        guard fsync(fd) == 0 else { throw VaultError.storage }
        try beforeCommit()
        if let expected {
            guard let current = try? read(), Self.digest(current) == expected else { throw VaultError.changedOnDisk }
        } else {
            var info = stat()
            guard lstat(url.path, &info) != 0, errno == ENOENT else { throw VaultError.changedOnDisk }
        }
        guard rename(temporary.path, url.path) == 0 else { throw VaultError.storage }
        // Rename is the commit point. A subsequent sync failure cannot safely undo it.
        let directory = open(parent.path, O_RDONLY)
        if directory >= 0 { _ = fsync(directory); close(directory) }
    }
}
