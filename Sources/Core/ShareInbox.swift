import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Private, bounded, versioned handoff. All filesystem access is anchored to an
/// opened directory descriptor; provider names never become filesystem paths.
public final class ShareInbox {
    public struct Item: Codable, Identifiable {
        public let id: UUID
        public let created: Date
        public let text: String
        public let files: [ChatAttachment]
    }
    private struct FileRecord: Codable { let id: UUID; let name: String; let mime: String; let bytes: Int }
    private struct Manifest: Codable { let version: Int; let id: UUID; let created: Date; let text: String; let files: [FileRecord] }
    public static let lifetime: TimeInterval = 7*24*60*60
    public static let maxItems = 16
    public static let maxText = 64*1024
    private let fd: Int32
    private let lock: Int32
    private let now: () -> Date
    public static let unavailable = "当前签名未启用共享容器，无法交接。请保留原内容并取消；主 App 与分享扩展须获准使用同一个 App Group。"
    public init(container: URL, now: @escaping () -> Date = Date.init) throws {
        self.now = now
        let fm = FileManager.default
        try fm.createDirectory(at: container, withIntermediateDirectories: true)
        let parent = open(container.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard parent >= 0 else { throw ClientError.message("共享目录不可用。") }
        defer { close(parent) }
        if mkdirat(parent, "QiuShare-v1", 0o700) != 0 && errno != EEXIST { throw ClientError.message("无法创建共享收件箱。") }
        fd = openat(parent, "QiuShare-v1", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw ClientError.message("共享收件箱路径不安全。") }
        lock = openat(fd, ".lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { close(fd); throw ClientError.message("共享收件箱锁不可用。") }
    }
    deinit { close(lock); close(fd) }
    private func locked<T>(_ body: () throws -> T) throws -> T {
        guard flock(lock, LOCK_EX) == 0 else { throw ClientError.message("收件箱正在使用，请重试。") }
        defer { flock(lock, LOCK_UN) }
        return try body()
    }
    private func ids() throws -> [UUID] {
        // fdopendir owns the duplicated descriptor. rewind before each listing.
        guard let dir = fdopendir(dup(fd)) else { throw ClientError.message("无法读取收件箱。") }
        defer { closedir(dir) }; rewinddir(dir)
        var result: [UUID] = []
        while let entry = readdir(dir) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) } }
            if let id = UUID(uuidString: name), name == id.uuidString { result.append(id) }
        }
        return result
    }
    private func directory(_ id: UUID) throws -> Int32 {
        let child = openat(fd, id.uuidString, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard child >= 0 else { throw ClientError.message("分享内容已不可用或路径不安全。") }
        return child
    }
    private func read(_ name: String, at parent: Int32, limit: Int) throws -> Data {
        let f = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard f >= 0 else { throw ClientError.message("分享文件不可用。") }
        defer { close(f) }
        var info = stat()
        guard fstat(f, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
              info.st_size >= 0, info.st_size <= limit else { throw ClientError.message("分享文件格式或大小不安全。") }
        let handle = FileHandle(fileDescriptor: f, closeOnDealloc: false)
        let data = try handle.read(upToCount: limit+1) ?? Data()
        guard data.count <= limit else { throw ClientError.message("分享文件超出上限。") }
        return data
    }
    private func write(_ data: Data, name: String, at parent: Int32) throws {
        let f = openat(parent, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard f >= 0 else { throw ClientError.message("无法写入分享文件。") }
        defer { close(f) }
        let handle = FileHandle(fileDescriptor: f, closeOnDealloc: false)
        try handle.write(contentsOf: data)
        guard fsync(f) == 0 else { throw ClientError.message("分享内容尚未安全保存。") }
    }
    private func manifest(_ id: UUID, at child: Int32) throws -> Manifest {
        let value = try JSONDecoder().decode(Manifest.self, from: read("manifest.json", at: child, limit: 128*1024))
        guard value.version == 1, value.id == id, value.files.count <= 4,
              value.text.utf8.count <= Self.maxText, Set(value.files.map(\.id)).count == value.files.count,
              value.created <= now().addingTimeInterval(300) else { throw ClientError.message("分享清单无效。") }
        return value
    }
    public func list() throws -> [Item] {
        try locked {
            try ids().map { id in
                let child = try directory(id); defer { close(child) }
                let m = try manifest(id, at: child)
                return Item(id: id, created: m.created, text: m.text, files: [])
            }.sorted { $0.created < $1.created }
        }
    }
    public func load(_ id: UUID) throws -> Item {
        try locked {
            let child = try directory(id); defer { close(child) }
            let m = try manifest(id, at: child)
            guard now().timeIntervalSince(m.created) <= Self.lifetime else { throw ClientError.message("分享已超过 7 天，请重新分享；可手动删除过期项。") }
            let files = try m.files.map { record -> ChatAttachment in
                guard record.bytes > 0, record.bytes <= AttachmentFailure.limit else { throw AttachmentFailure(.fileSize, bytes: record.bytes) }
                let bytes = try read(record.id.uuidString, at: child, limit: AttachmentFailure.limit)
                guard bytes.count == record.bytes else { throw ClientError.message("分享文件不完整，未导入任何内容。") }
                return try ChatAttachment(name: record.name, mime: record.mime, data: bytes)
            }
            try Self.validate(text: m.text, files: files)
            return Item(id: id, created: m.created, text: m.text, files: files)
        }
    }
    public static func validate(text: String, files: [ChatAttachment]) throws {
        guard text.utf8.count <= maxText else { throw ClientError.message("分享文字超过 64 KiB，未截断保存。") }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !files.isEmpty else { throw ClientError.message("没有可保存的分享内容。") }
        try AttachmentFailure.validateMessage(count: files.count, bytes: files.reduce(0) { $0+$1.data.count })
        for f in files { _ = try ChatAttachment(name: f.name, mime: f.mime, data: f.data) }
    }
    public func save(text: String, files: [ChatAttachment]) throws -> UUID {
        try Self.validate(text: text, files: files)
        return try locked {
            guard try ids().count < Self.maxItems else { throw ClientError.message("分享收件箱已满（16 项），请先在球球中导入或删除；本次未保存。") }
            let id = UUID(), staging = ".stage-"+UUID().uuidString
            guard mkdirat(fd, staging, 0o700) == 0 else { throw ClientError.message("无法开始保存分享。") }
            let child = openat(fd, staging, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard child >= 0 else { unlinkat(fd, staging, AT_REMOVEDIR); throw ClientError.message("分享保存失败。") }
            var written: [String] = []; var committed = false
            defer {
                if !committed { for name in written { unlinkat(child, name, 0) }; unlinkat(child, "manifest.json", 0); unlinkat(fd, staging, AT_REMOVEDIR) }
                close(child)
            }
            var records: [FileRecord] = []
            for f in files {
                let fileID = UUID(); written.append(fileID.uuidString)
                try write(f.data, name: fileID.uuidString, at: child)
                records.append(FileRecord(id: fileID, name: f.name, mime: f.mime, bytes: f.data.count))
            }
            let m = Manifest(version: 1, id: id, created: now(), text: text, files: records)
            try write(JSONEncoder().encode(m), name: "manifest.json", at: child)
            guard fsync(child) == 0, renameat(fd, staging, fd, id.uuidString) == 0 else { throw ClientError.message("分享提交失败，未显示保存成功。") }
            committed = true
            // The complete directory is now visible; never report failure after
            // commit (which could cause duplicate user retries).
            _ = fsync(fd)
            return id
        }
    }
    public func remove(_ id: UUID) throws {
        try locked {
            let child = try directory(id); defer { close(child) }
            let m = try manifest(id, at: child)
            // Opaque names from UUID fields only; unlink never follows symlinks.
            for file in m.files { if unlinkat(child, file.id.uuidString, 0) != 0 && errno != ENOENT { throw ClientError.message("删除分享失败。") } }
            guard unlinkat(child, "manifest.json", 0) == 0, unlinkat(fd, id.uuidString, AT_REMOVEDIR) == 0 else { throw ClientError.message("删除分享未完成。") }
        }
    }
    /// Actual disposable read/write canary, no private paths in its result.
    public func checkWritable() throws {
        try locked {
            let name = ".probe-"+UUID().uuidString, data = Data(UUID().uuidString.utf8)
            defer { unlinkat(fd, name, 0) }
            try write(data, name: name, at: fd)
            guard try read(name, at: fd, limit: 128) == data else { throw ClientError.message("共享容器读写验证失败。") }
        }
    }
}
