import Foundation
import GRDB

final class MessagesReader {
    private let databasePath: String
    private let batchLimit: Int

    init(
        databasePath: String = ("~/Library/Messages/chat.db" as NSString).expandingTildeInPath,
        batchLimit: Int = 250
    ) {
        self.databasePath = databasePath
        self.batchLimit = batchLimit
    }

    func canReadMessagesDatabase() -> Bool {
        do {
            _ = try openDatabase()
            return true
        } catch {
            return false
        }
    }

    func readBatch(after rowId: Int64) throws -> SyncBatch {
        let queue = try openDatabase()
        let rows: [MessageRow] = try queue.read { db in
            if rowId <= 0 {
                return try readMostRecentRows(db)
            }
            return try readRows(db, after: rowId)
        }

        let sortedRows = rows.sorted { $0.rowId < $1.rowId }
        let threads = Dictionary(
            sortedRows.map { row in
                (
                    row.threadGuid,
                    BridgeThread(
                        sourceThreadId: row.threadGuid,
                        threadName: row.threadName,
                        participants: row.participantList
                    )
                )
            },
            uniquingKeysWith: { current, next in
                BridgeThread(
                    sourceThreadId: current.sourceThreadId,
                    threadName: next.threadName ?? current.threadName,
                    participants: Array(Set(current.participants + next.participants)).sorted()
                )
            }
        )

        let messages = sortedRows.map { row in
            BridgeMessage(
                sourceMessageId: row.messageGuid,
                sourceRowId: row.rowId,
                sourceThreadId: row.threadGuid,
                direction: row.isFromMe ? "sent" : "received",
                service: row.service ?? "unknown",
                body: row.body,
                sentAt: row.sentAt
            )
        }

        return SyncBatch(
            threads: Array(threads.values),
            messages: messages,
            lastSyncedRowId: messages.map(\.sourceRowId).max() ?? rowId
        )
    }

    private func readRows(_ db: Database, after rowId: Int64) throws -> [MessageRow] {
        try MessageRow.fetchAll(
            db,
            sql: """
            SELECT
              message.ROWID AS rowId,
              message.guid AS messageGuid,
              message.text AS body,
              message.is_from_me AS isFromMe,
              message.service AS service,
              message.date AS messageDate,
              chat.guid AS threadGuid,
              chat.display_name AS threadName,
              GROUP_CONCAT(handle.id, '\u{001F}') AS participants
            FROM message
            INNER JOIN chat_message_join ON chat_message_join.message_id = message.ROWID
            INNER JOIN chat ON chat.ROWID = chat_message_join.chat_id
            LEFT JOIN chat_handle_join ON chat_handle_join.chat_id = chat.ROWID
            LEFT JOIN handle ON handle.ROWID = chat_handle_join.handle_id
            WHERE message.ROWID > ?
              AND message.guid IS NOT NULL
              AND message.text IS NOT NULL
              AND length(trim(message.text)) > 0
            GROUP BY message.ROWID
            ORDER BY message.ROWID ASC
            LIMIT ?
            """,
            arguments: [rowId, batchLimit]
        )
    }

    private func readMostRecentRows(_ db: Database) throws -> [MessageRow] {
        try MessageRow.fetchAll(
            db,
            sql: """
            SELECT * FROM (
              SELECT
                message.ROWID AS rowId,
                message.guid AS messageGuid,
                message.text AS body,
                message.is_from_me AS isFromMe,
                message.service AS service,
                message.date AS messageDate,
                chat.guid AS threadGuid,
                chat.display_name AS threadName,
                GROUP_CONCAT(handle.id, '\u{001F}') AS participants
              FROM message
              INNER JOIN chat_message_join ON chat_message_join.message_id = message.ROWID
              INNER JOIN chat ON chat.ROWID = chat_message_join.chat_id
              LEFT JOIN chat_handle_join ON chat_handle_join.chat_id = chat.ROWID
              LEFT JOIN handle ON handle.ROWID = chat_handle_join.handle_id
              WHERE message.guid IS NOT NULL
                AND message.text IS NOT NULL
                AND length(trim(message.text)) > 0
              GROUP BY message.ROWID
              ORDER BY message.ROWID DESC
              LIMIT ?
            )
            ORDER BY rowId ASC
            """,
            arguments: [batchLimit]
        )
    }

    private func openDatabase() throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.readonly = true
        return try DatabaseQueue(path: databasePath, configuration: configuration)
    }
}

private struct MessageRow: FetchableRecord, Decodable {
    let rowId: Int64
    let messageGuid: String
    let body: String
    let isFromMeRaw: Int
    let service: String?
    let messageDate: Int64
    let threadGuid: String
    let threadName: String?
    let participants: String?

    enum CodingKeys: String, CodingKey {
        case rowId
        case messageGuid
        case body
        case isFromMeRaw = "isFromMe"
        case service
        case messageDate
        case threadGuid
        case threadName
        case participants
    }

    var isFromMe: Bool {
        isFromMeRaw == 1
    }

    var participantList: [String] {
        participants?
            .split(separator: "\u{001F}")
            .map(String.init)
            .filter { !$0.isEmpty } ?? []
    }

    var sentAt: Date {
        Date(timeIntervalSinceReferenceDate: TimeInterval(messageDate) / 1_000_000_000)
    }
}
