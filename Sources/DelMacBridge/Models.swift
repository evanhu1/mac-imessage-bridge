import Foundation

struct AppConfiguration: Codable, Equatable {
    var apiBaseURL: URL
    var deviceId: String
    var deviceName: String
}

struct PairingCompleteResponse: Decodable {
    let ok: Bool?
    let deviceId: String
    let deviceToken: String
}

struct SyncResponse: Decodable {
    let ok: Bool
    let syncedMessages: Int
    let lastSyncedRowId: Int64
}

struct BridgeThread: Codable, Hashable {
    let sourceThreadId: String
    let threadName: String?
    let participants: [String]
}

struct BridgeMessage: Codable, Hashable {
    let sourceMessageId: String
    let sourceRowId: Int64
    let sourceThreadId: String
    let direction: String
    let service: String
    let body: String
    let sentAt: Date
}

struct SyncBatch: Codable {
    let threads: [BridgeThread]
    let messages: [BridgeMessage]
    let lastSyncedRowId: Int64
}

enum BridgeStatus: Equatable {
    case notPaired
    case needsFullDiskAccess
    case waitingForFullDiskAccess
    case ready
    case syncing
    case paused
    case error(String)

    var title: String {
        switch self {
        case .notPaired:
            return "Not paired"
        case .needsFullDiskAccess:
            return "Needs Full Disk Access"
        case .waitingForFullDiskAccess:
            return "Waiting for Full Disk Access"
        case .ready:
            return "Connected"
        case .syncing:
            return "Syncing"
        case .paused:
            return "Paused"
        case .error:
            return "Error"
        }
    }
}
