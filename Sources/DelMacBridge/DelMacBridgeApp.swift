import AppKit
import SwiftUI

@main
struct DelMacBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
        registerURLHandler()
        appState.refreshStatus()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "message.badge", accessibilityDescription: "Del Messages")
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(togglePopover)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 420)
        popover.contentViewController = NSHostingController(
            rootView: MenuPopoverView(appState: appState)
        )
    }

    private func registerURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(event:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    @objc private func handleGetURLEvent(
        event: NSAppleEventDescriptor,
        replyEvent: NSAppleEventDescriptor
    ) {
        guard
            let rawURL = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: rawURL)
        else {
            return
        }

        showPopover()
        appState.handlePairingURL(url)
    }

    private func showPopover() {
        appState.refreshStatus()
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

// MARK: - Root popover

private struct MenuPopoverView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    StatusCard(appState: appState)
                    PrivacyCard()
                }
                .padding(10)
            }

            Divider()

            FooterToolbar(appState: appState)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(width: 320)
        .background(.regularMaterial)
    }
}

// MARK: - Header

private struct HeaderBar: View {
    @Bindable var appState: AppState

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.accentColor.opacity(0.85), Color.accentColor.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 30, height: 30)
                Image(systemName: "message.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Del Messages")
                    .font(.system(size: 13, weight: .semibold))
                if let deviceName = appState.configuration?.deviceName {
                    Text(deviceName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Menu bar bridge")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            StatusPill(status: appState.status)
        }
    }
}

private struct StatusPill: View {
    let status: BridgeStatus

    var body: some View {
        HStack(spacing: 6) {
            StatusIndicator(status: status)
            Text(status.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(textColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(borderColor, lineWidth: 0.5)
        )
    }

    private var backgroundColor: Color {
        switch status {
        case .ready, .syncing:
            return Color.green.opacity(0.14)
        case .paused:
            return Color.secondary.opacity(0.12)
        case .needsFullDiskAccess, .waitingForFullDiskAccess:
            return Color.orange.opacity(0.14)
        case .error:
            return Color.red.opacity(0.14)
        case .notPaired:
            return Color.secondary.opacity(0.12)
        }
    }

    private var borderColor: Color {
        switch status {
        case .ready, .syncing:
            return Color.green.opacity(0.25)
        case .needsFullDiskAccess, .waitingForFullDiskAccess:
            return Color.orange.opacity(0.25)
        case .error:
            return Color.red.opacity(0.25)
        default:
            return Color.secondary.opacity(0.18)
        }
    }

    private var textColor: Color {
        switch status {
        case .ready, .syncing:
            return .green
        case .needsFullDiskAccess, .waitingForFullDiskAccess:
            return .orange
        case .error:
            return .red
        default:
            return .secondary
        }
    }
}

private struct StatusIndicator: View {
    let status: BridgeStatus
    @State private var isAnimating = false

    var body: some View {
        Group {
            switch status {
            case .syncing:
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 8, height: 8)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(
                        .linear(duration: 0.9).repeatForever(autoreverses: false),
                        value: isAnimating
                    )
                    .onAppear { isAnimating = true }
            case .ready:
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .fill(.green.opacity(0.35))
                            .frame(width: 13, height: 13)
                            .blur(radius: 2)
                    )
            case .paused:
                Image(systemName: "pause.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            case .needsFullDiskAccess, .waitingForFullDiskAccess:
                Circle()
                    .fill(.orange)
                    .frame(width: 7, height: 7)
            case .error:
                Image(systemName: "exclamationmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.red)
            case .notPaired:
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
            }
        }
        .frame(width: 13, height: 13)
    }
}

// MARK: - Status card (state-driven body)

private struct StatusCard: View {
    @Bindable var appState: AppState

    var body: some View {
        switch appState.status {
        case .notPaired:
            NotPairedCard(appState: appState)
        case .needsFullDiskAccess, .waitingForFullDiskAccess:
            FullDiskAccessCard(appState: appState)
        case .ready, .syncing:
            ConnectedCard(appState: appState)
        case .paused:
            PausedCard(appState: appState)
        case .error(let message):
            ErrorCard(appState: appState, message: message)
        }
    }
}

// MARK: - Card chrome

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
    }
}

private struct CardHeader: View {
    let symbol: String
    let symbolColor: Color
    let title: String
    let subtitle: String?

    init(symbol: String, symbolColor: Color = .accentColor, title: String, subtitle: String? = nil) {
        self.symbol = symbol
        self.symbolColor = symbolColor
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(symbolColor)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - State-specific cards

private struct NotPairedCard: View {
    @Bindable var appState: AppState

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(
                    symbol: "link.badge.plus",
                    symbolColor: .secondary,
                    title: "Pair this Mac with Del",
                    subtitle: "Open Del in your browser, then click Connect on the Messages card to pair this device."
                )

                Button {
                    appState.openDel()
                } label: {
                    Label("Open Del to pair", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
    }
}

private struct FullDiskAccessCard: View {
    @Bindable var appState: AppState

    private var isWaiting: Bool {
        appState.status == .waitingForFullDiskAccess
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(
                    symbol: "lock.shield.fill",
                    symbolColor: .orange,
                    title: isWaiting ? "Waiting for permission" : "Grant Full Disk Access",
                    subtitle: "macOS requires Full Disk Access before any app can read your local Messages database."
                )

                VStack(alignment: .leading, spacing: 8) {
                    PermissionStep(
                        number: 1,
                        text: "Click the button below to open System Settings."
                    )
                    PermissionStep(
                        number: 2,
                        text: "Find Del Messages under Full Disk Access and turn it on."
                    )
                    PermissionStep(
                        number: 3,
                        text: "Return here. This menu updates automatically."
                    )
                }
                .padding(.leading, 2)

                Button {
                    appState.openFullDiskAccessSettings()
                } label: {
                    Label(
                        isWaiting ? "Open Settings again" : "Grant Full Disk Access",
                        systemImage: "gear"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                if appState.isWatchingFullDiskAccess {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                        Text("Checking every two seconds…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }
}

private struct PermissionStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .background(
                    Circle()
                        .fill(Color.secondary.opacity(0.15))
                )
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ConnectedCard: View {
    @Bindable var appState: AppState

    private var isSyncing: Bool { appState.status == .syncing }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(.green.opacity(0.18))
                            .frame(width: 32, height: 32)
                        Circle()
                            .fill(.green)
                            .frame(width: 10, height: 10)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(isSyncing ? "Syncing now…" : "Connected")
                            .font(.system(size: 14, weight: .semibold))
                        Text(isSyncing ? "Reading new messages" : "Watching for new messages")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Divider()
                    .opacity(0.4)

                VStack(spacing: 6) {
                    InfoRow(
                        label: "Last sync",
                        value: lastSyncString
                    )
                    if let deviceName = appState.configuration?.deviceName {
                        InfoRow(label: "Device", value: deviceName)
                    }
                    InfoRow(
                        label: "Auto-sync",
                        value: "Every 30 seconds"
                    )
                }
            }
        }
    }

    private var lastSyncString: String {
        guard let date = appState.lastSyncAt else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct PausedCard: View {
    @Bindable var appState: AppState

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(
                    symbol: "pause.circle.fill",
                    symbolColor: .secondary,
                    title: "Sync paused",
                    subtitle: "Del Messages will not read or upload any new messages until you resume."
                )

                Button {
                    appState.togglePaused()
                } label: {
                    Label("Resume syncing", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
    }
}

private struct ErrorCard: View {
    @Bindable var appState: AppState
    let message: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(
                    symbol: "exclamationmark.triangle.fill",
                    symbolColor: .red,
                    title: "Something went wrong",
                    subtitle: message
                )

                Button {
                    Task { await appState.syncOnce() }
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
    }
}

// MARK: - Privacy card

private struct PrivacyCard: View {
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("What Del does on your Mac")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 7) {
                    PrivacyRow(symbol: "checkmark", color: .green, text: "Syncs message text only")
                    PrivacyRow(symbol: "xmark", color: .secondary, text: "Never sends replies on your behalf")
                    PrivacyRow(symbol: "xmark", color: .secondary, text: "Never modifies your Messages app")
                    PrivacyRow(symbol: "xmark", color: .secondary, text: "Does not create tasks from messages")
                }
            }
        }
    }
}

private struct PrivacyRow: View {
    let symbol: String
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 14, height: 14)
                .background(
                    Circle()
                        .fill(color.opacity(0.14))
                )
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.primary.opacity(0.85))
        }
    }
}

// MARK: - Footer toolbar

private struct FooterToolbar: View {
    @Bindable var appState: AppState

    private var canPause: Bool {
        appState.configuration != nil
    }

    private var canDisconnect: Bool {
        appState.configuration != nil
    }

    var body: some View {
        HStack(spacing: 4) {
            ToolbarIconButton(
                symbol: appState.isPaused ? "play.fill" : "pause.fill",
                tooltip: appState.isPaused ? "Resume" : "Pause syncing",
                isDisabled: !canPause
            ) {
                appState.togglePaused()
            }

            ToolbarIconButton(
                symbol: "safari",
                tooltip: "Open Del"
            ) {
                appState.openDel()
            }

            Spacer()

            Menu {
                Button("Disconnect this Mac", role: .destructive) {
                    appState.disconnect()
                }
                .disabled(!canDisconnect)
                Divider()
                Button("Quit Del Messages") {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
    }
}

private struct ToolbarIconButton: View {
    let symbol: String
    let tooltip: String
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isDisabled ? Color.secondary.opacity(0.5) : .primary.opacity(0.85))
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovering && !isDisabled ? Color.primary.opacity(0.08) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(tooltip)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
