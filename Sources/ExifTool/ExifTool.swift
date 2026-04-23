import CExifToolBridge
import Foundation

public struct ExifToolVersions: Codable, Equatable, Sendable {
    public let exiftool: String
    public let perl: String
}

public struct ExifToolWriteResult: Codable, Equatable, Sendable {
    public let success: Bool
    public let error: String?
    public let warning: String?
}

public enum ExifToolError: Error, Equatable, Sendable {
    case runtime(String)
    case invalidPayload(String)
}

public final class ExifToolRuntime {
    private let handle: OpaquePointer

    public init(moduleRoot: URL? = nil) throws {
        var runtime: OpaquePointer?
        let resolvedRoot = moduleRoot ?? Bundle.module.resourceURL!.appending(path: "Perl")
        let result = exiftool_runtime_create(resolvedRoot.path, &runtime)

        _ = try Self.consume(result)
        guard let runtime else {
            throw ExifToolError.runtime("Embedded ExifTool runtime was not created")
        }

        self.handle = runtime
    }

    deinit {
        exiftool_runtime_destroy(handle)
    }

    public func makeSession() throws -> ExifToolSession {
        var session: OpaquePointer?
        let result = exiftool_session_create(handle, &session)

        _ = try Self.consume(result)
        guard let session else {
            throw ExifToolError.runtime("ExifTool session creation returned an empty handle")
        }

        return ExifToolSession(handle: session)
    }

    public func versions() throws -> ExifToolVersions {
        let payload = try Self.consume(exiftool_runtime_versions_json(handle))
        return try Self.decodePayload(ExifToolVersions.self, payload: payload)
    }

    fileprivate static func consume(_ result: exiftool_result_t) throws -> String {
        let mutableResult = result
        defer {
            exiftool_result_destroy(mutableResult)
        }

        if mutableResult.status != EXIFTOOL_STATUS_OK {
            let message = mutableResult.error_message.map { String(cString: $0) } ?? "Unknown ExifTool error"
            throw ExifToolError.runtime(message)
        }

        guard let payload = mutableResult.payload else {
            return ""
        }

        return String(cString: payload)
    }

    private static func decodePayload<T: Decodable>(_ type: T.Type, payload: String) throws -> T {
        guard let data = payload.data(using: .utf8) else {
            throw ExifToolError.invalidPayload("Result payload is not valid UTF-8")
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    fileprivate static func encodeJSON(_ value: some Encodable) throws -> String {
        let data = try JSONEncoder().encode(value)

        guard let string = String(data: data, encoding: .utf8) else {
            throw ExifToolError.invalidPayload("JSON encoding did not produce UTF-8")
        }

        return string
    }

    fileprivate static func encodeTagsPayload(_ tags: [String]) -> String {
        tags.joined(separator: "\n")
    }

    fileprivate static func encodeAssignmentsPayload(_ values: [String: JSONValue]) throws -> String {
        try values.keys.sorted().map { key in
            let (typeCode, payload) = try encodeAssignmentValue(values[key]!)
            return "\(key)\t\(typeCode)\t\(payload)"
        }.joined(separator: "\n")
    }

    private static func encodeAssignmentValue(_ value: JSONValue) throws -> (String, String) {
        switch value {
        case .string(let string):
            let bytes = Data(string.utf8).map { String(format: "%02x", $0) }.joined()
            return ("s", bytes)
        case .number(let number):
            return ("n", String(number))
        case .bool(let bool):
            return ("b", bool ? "1" : "0")
        case .null:
            return ("z", "")
        case .array, .object:
            throw ExifToolError.invalidPayload("Complex write values are not supported by the embedded serializer")
        }
    }
}

public final class ExifToolSession {
    private let handle: OpaquePointer

    fileprivate init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        exiftool_session_destroy(handle)
    }

    public func readMetadataJSON(at fileURL: URL, tags: [String] = []) throws -> String {
        let tagsPayload = tags.isEmpty ? nil : ExifToolRuntime.encodeTagsPayload(tags)
        let result = exiftool_session_read_metadata_json(handle, fileURL.path, tagsPayload)
        return try ExifToolRuntime.consume(result)
    }

    public func readMetadata(
        at fileURL: URL,
        tags: [String] = []
    ) throws -> [String: JSONValue] {
        let payload = try readMetadataJSON(at: fileURL, tags: tags)
        guard let data = payload.data(using: .utf8) else {
            throw ExifToolError.invalidPayload("Metadata payload is not valid UTF-8")
        }

        return try JSONDecoder().decode([String: JSONValue].self, from: data)
    }

    public func writeMetadata(
        from sourceURL: URL,
        to destinationURL: URL? = nil,
        values: [String: JSONValue]
    ) throws -> ExifToolWriteResult {
        let assignmentsPayload = try ExifToolRuntime.encodeAssignmentsPayload(values)
        let result = exiftool_session_write_metadata_json(
            handle,
            sourceURL.path,
            destinationURL?.path,
            assignmentsPayload
        )
        let payload = try ExifToolRuntime.consume(result)

        guard let data = payload.data(using: .utf8) else {
            throw ExifToolError.invalidPayload("Write result payload is not valid UTF-8")
        }

        return try JSONDecoder().decode(ExifToolWriteResult.self, from: data)
    }
}
