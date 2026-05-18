import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var status: BridgeStatus = .notPaired
    var isPaused = false
    var lastSyncAt: Date?
    var lastSyncedRowId: Int64 = 0
    var configuration: AppConfiguration?
    var isWatchingFullDiskAccess = false
    var isConnected = false

    private let apiClient = APIClient()
    private let keychain = KeychainStore.shared
    private let messagesReader = MessagesReader()
    private var syncTask: Task<Void, Never>?
    private var fullDiskAccessTask: Task<Void, Never>?

    init() {
        configuration = keychain.loadConfiguration()
        lastSyncedRowId = Int64(UserDefaults.standard.integer(forKey: "lastSyncedRowId"))
        refreshStatus()
        startSyncLoop()
    }

    func handlePairingURL(_ url: URL) {
        guard
            url.scheme == "del-mac",
            url.host == "pair",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
            let apiBaseURLValue = components.queryItems?.first(where: { $0.name == "apiBaseUrl" })?.value,
            let apiBaseURL = URL(string: apiBaseURLValue)
        else {
            status = .error("Invalid pairing link.")
            return
        }

        Task {
            await completePairing(apiBaseURL: apiBaseURL, token: token)
        }
    }

    func completePairing(apiBaseURL: URL, token: String) async {
        do {
            status = .syncing
            let deviceName = Host.current().localizedName ?? "Mac"
            let response = try await apiClient.completePairing(
                apiBaseURL: apiBaseURL,
                token: token,
                deviceName: deviceName
            )
            try keychain.saveDeviceToken(response.deviceToken)
            let nextConfiguration = AppConfiguration(
                apiBaseURL: apiBaseURL,
                deviceId: response.deviceId,
                deviceName: deviceName
            )
            try keychain.saveConfiguration(nextConfiguration)
            configuration = nextConfiguration
            refreshStatus()
            await syncOnce()
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    func togglePaused() {
        isPaused.toggle()
        refreshStatus()
    }

    func disconnect() {
        keychain.deleteDeviceToken()
        keychain.deleteConfiguration()
        configuration = nil
        lastSyncedRowId = 0
        UserDefaults.standard.removeObject(forKey: "lastSyncedRowId")
        refreshStatus()
    }

    func syncOnce() async {
        guard !isPaused else {
            status = .paused
            return
        }
        guard let configuration, let token = keychain.loadDeviceToken() else {
            isConnected = false
            status = .notPaired
            return
        }
        guard messagesReader.canReadMessagesDatabase() else {
            isConnected = false
            status = isWatchingFullDiskAccess ? .waitingForFullDiskAccess : .needsFullDiskAccess
            return
        }

        do {
            isConnected = true
            status = .syncing
            let batch = try messagesReader.readBatch(after: lastSyncedRowId)
            if batch.messages.isEmpty {
                lastSyncAt = Date()
                status = .ready
                return
            }
            let response = try await apiClient.sync(
                apiBaseURL: configuration.apiBaseURL,
                deviceToken: token,
                batch: batch
            )
            lastSyncedRowId = response.lastSyncedRowId
            UserDefaults.standard.set(lastSyncedRowId, forKey: "lastSyncedRowId")
            lastSyncAt = Date()
            status = .ready
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    func openFullDiskAccessSettings() {
        startFullDiskAccessWatcher()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func openDel() {
        guard let url = configuration?.apiBaseURL ?? URL(string: "http://localhost:3000") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func refreshStatus() {
        if isPaused {
            status = .paused
        } else if configuration == nil || keychain.loadDeviceToken() == nil {
            stopFullDiskAccessWatcher()
            isConnected = false
            status = .notPaired
        } else if !messagesReader.canReadMessagesDatabase() {
            isConnected = false
            status = isWatchingFullDiskAccess ? .waitingForFullDiskAccess : .needsFullDiskAccess
        } else {
            stopFullDiskAccessWatcher()
            isConnected = true
            status = .ready
        }
    }

    private func startSyncLoop() {
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncOnce()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func startFullDiskAccessWatcher() {
        isWatchingFullDiskAccess = true
        status = .waitingForFullDiskAccess
        fullDiskAccessTask?.cancel()
        fullDiskAccessTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.messagesReader.canReadMessagesDatabase() {
                    self.stopFullDiskAccessWatcher()
                    self.refreshStatus()
                    await self.syncOnce()
                    return
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func stopFullDiskAccessWatcher() {
        isWatchingFullDiskAccess = false
        fullDiskAccessTask?.cancel()
        fullDiskAccessTask = nil
    }
}
