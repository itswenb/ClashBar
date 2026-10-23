import AppKit
import Combine
import SwiftUI
import XCTest
@testable import ClashBar

private enum NavigationTestReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var navigationTestReduceMotion: Bool {
        get { self[NavigationTestReduceMotionKey.self] }
        set { self[NavigationTestReduceMotionKey.self] = newValue }
    }
}

final class MenuBarNavigationTests: XCTestCase {
    @MainActor
    func testRapidTabChangesKeepFinalSelectionAndRecalculateHeight() throws {
        try self.exerciseNavigation(reduceMotion: false, colorScheme: .dark)
    }

    @MainActor
    func testReducedMotionNavigationRecalculatesHeight() throws {
        try self.exerciseNavigation(reduceMotion: true, colorScheme: .light)
    }

    @MainActor
    private func exerciseNavigation(reduceMotion: Bool, colorScheme: ColorScheme) throws {
        let app = NSApplication.shared
        guard let screen = NSScreen.main else {
            throw XCTSkip("Requires a macOS window server")
        }
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)
        let initialPanelIDs = Set(app.windows.filter { $0 is NSPanel }.map(ObjectIdentifier.init))

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let working = WorkingDirectoryManager(homeDirectory: directory)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ClashBar.NavigationTests.\(UUID().uuidString)"))
        let machines = RemoteMachineStore(session: URLSession(configuration: .ephemeral), defaults: defaults)
        let model = AppViewModel(dependencies: AppDependencies(
            processManager: MihomoProcessManager(workingDirectoryManager: working),
            configService: ConfigService(
                configManager: ConfigDirectoryManager(workingDirectoryManager: working),
                configImportService: ConfigImportService()),
            systemProxyService: SystemProxyService(),
            tunPermissionService: TunPermissionService(),
            launchAtLoginService: AppLaunchService(),
            workingDirectoryManager: working,
            networkReachabilityMonitor: NetworkReachabilityMonitor(),
            ssidMonitorService: SSIDMonitorService(),
            remoteMachineStore: machines,
            proxyGroupIconCache: .unavailable,
            clashbarLogStore: AppLogStore(logFileURL: directory.appendingPathComponent("app.log")),
            mihomoLogStore: AppLogStore(logFileURL: directory.appendingPathComponent("core.log"))))
        model.uiLanguage = .zhHans

        let previousDefaults = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var isolatedDefaults = previousDefaults
        isolatedDefaults[model.systemProxyEnabledOnQuitKey] = false
        isolatedDefaults["AppleShowScrollBars"] = "Always"
        UserDefaults.standard.setVolatileDomain(isolatedDefaults, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(previousDefaults, forName: UserDefaults.argumentDomain) }

        let layout = PopoverLayoutModel(maxPanelHeight: 640, preferredPanelHeight: 640)
        let root = MenuBarRootView(reduceMotion: Environment(\.navigationTestReduceMotion))
            .environmentObject(model)
            .environmentObject(model.proxyStore)
            .environmentObject(model.trafficStore)
            .environmentObject(model.logsStore)
            .environmentObject(model.connectionsStore)
            .environmentObject(machines)
            .environmentObject(layout)
            .environment(\.colorScheme, colorScheme)
            .environment(\.navigationTestReduceMotion, reduceMotion)
            .frame(width: 360, alignment: .topLeading)
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: screen.visibleFrame.minX + 100, y: screen.visibleFrame.minY + 100,
                                width: 360, height: 640),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer {
            window.contentView = nil
            window.close()
            model.cancelOwnedTasks()
            try? FileManager.default.removeItem(at: directory)
        }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let initialHeight = layout.resolvedPanelHeight

        model.activeMenuTab = .system
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let settingsHeight = layout.resolvedPanelHeight
        XCTAssertGreaterThan(settingsHeight, initialHeight)
        model.activeMenuTab = .logs
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let logsHeight = layout.resolvedPanelHeight
        XCTAssertLessThan(logsHeight, settingsHeight)
        layout.resizePanelHeight(to: 580, minimum: 280)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(layout.resolvedPanelHeight, 580, accuracy: 0.5)
        model.activeMenuTab = .system
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertNil(layout.userPanelHeight)
        XCTAssertEqual(layout.resolvedPanelHeight, settingsHeight, accuracy: 0.5)

        for (index, tab) in [RootTab.system, .connections, .rules, .proxy, .logs].enumerated() {
            let column = try XCTUnwrap(RootTab.allCases.firstIndex(of: tab))
            let x = 8 + CGFloat(column) * 69.2 + 33.6
            for (offset, type) in [NSEvent.EventType.leftMouseDown, .leftMouseUp].enumerated() {
                let event = try XCTUnwrap(NSEvent.mouseEvent(
                    with: type, location: NSPoint(x: x, y: 534), modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: index * 2 + offset + 1, clickCount: 1, pressure: 1))
                app.sendEvent(event)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            XCTAssertEqual(model.activeMenuTab, tab)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        XCTAssertEqual(model.activeMenuTab, .logs)
        XCTAssertEqual(layout.resolvedPanelHeight, logsHeight, accuracy: 0.5)

        model.proxyStore.proxyGroups = (0..<50).map {
            ProxyGroup(name: "Group \($0)", type: "Selector", now: "DIRECT", all: ["DIRECT"])
        }
        model.proxyStore.ruleItems = (0..<50).map {
            RuleItem(type: "DOMAIN", payload: "host\($0).example", proxy: "DIRECT")
        }
        model.proxyStore.rulesCount = 50
        model.connectionsStore.connections = (0..<50).map {
            ConnectionSummary(id: "\($0)", upload: 128, download: 256, start: nil,
                              rule: "DOMAIN", rulePayload: "host\($0).example", chains: ["DIRECT"], metadata: nil)
        }
        model.connectionsStore.connectionsCount = 50
        model.logsStore.errorLogs = (0..<50).map {
            AppErrorLogEntry(level: "info", message: "Connection \($0) established")
        }

        for tab in RootTab.allCases {
            model.activeMenuTab = tab
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            let scroll = try self.contentScrollView(in: hosting)
            let unusedPanels = app.windows.filter { $0 is NSPanel && !initialPanelIDs.contains(ObjectIdentifier($0)) }
            XCTAssertEqual(unusedPanels.count, 0, "Unopened menus should not allocate native panels: \(tab)")
            XCTAssertFalse(scroll.hasVerticalScroller, "Unexpected scrollbar after switching to \(tab)")
            XCTAssertEqual(scroll.contentView.frame.width, scroll.bounds.width, accuracy: 0.5,
                           "Scrollbar must not reserve a gutter: \(tab)")
            let frame = scroll.convert(scroll.bounds, to: nil)
            let fixedTopHeight = 640 - frame.maxY
            XCTAssertGreaterThan(fixedTopHeight, tab == .system ? 110 : 160, "\(tab)")
            XCTAssertGreaterThanOrEqual(frame.minY, 640 - layout.resolvedPanelHeight + 23, "Footer: \(tab) \(frame)")
            let document = try XCTUnwrap(scroll.documentView)
            XCTAssertGreaterThan(document.bounds.height, scroll.contentView.bounds.height, "\(tab)")
            scroll.contentView.scroll(to: NSPoint(x: 0, y: 150))
            scroll.reflectScrolledClipView(scroll.contentView)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0, "\(tab)")
            XCTAssertFalse(scroll.hasVerticalScroller, "Unexpected scrollbar while scrolling \(tab)")
            XCTAssertEqual(scroll.convert(scroll.bounds, to: nil).maxY, frame.maxY, accuracy: 0.5, "\(tab)")
            XCTAssertGreaterThanOrEqual(scroll.convert(scroll.bounds, to: nil).minY,
                                        640 - layout.resolvedPanelHeight + 23, "Scrolled footer: \(tab)")
        }

        model.activeMenuTab = .proxy
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let returnedScroll = try self.contentScrollView(in: hosting)
        XCTAssertFalse(returnedScroll.hasVerticalScroller, "Scrollbar reappeared when returning to nodes")
        XCTAssertEqual(returnedScroll.contentView.frame.width, returnedScroll.bounds.width, accuracy: 0.5)
        let localScrollTop = try self.contentScrollView(in: hosting).convert(
            self.contentScrollView(in: hosting).bounds, to: nil).maxY
        let remote = RemoteMachine(name: "Test Router", host: "192.0.2.10")
        machines.machines = [remote]
        machines.activeTargetID = remote.id
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let remoteScroll = try self.contentScrollView(in: hosting)
        XCTAssertTrue(model.isRemoteTarget)
        XCTAssertGreaterThan(remoteScroll.convert(remoteScroll.bounds, to: nil).maxY - localScrollTop, 30)

        let decorationHeight = window.frame.height - hosting.bounds.height
        let windowTop = window.frame.maxY
        let heightSubscription = layout.$resolvedPanelHeight
            .receive(on: RunLoop.main)
            .sink { [weak window] height in
                guard let window else { return }
                window.setFrame(NSRect(x: window.frame.minX, y: windowTop - height - decorationHeight,
                                       width: 360, height: height + decorationHeight), display: true)
            }
        defer { heightSubscription.cancel() }
        layout.resizePanelHeight(to: 480, minimum: 280)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let dragStart = NSPoint(x: 338, y: 12)
        try self.drag(in: window, from: dragStart, deltaY: 0, deltaX: 80)
        XCTAssertEqual(layout.resolvedPanelHeight, 480, accuracy: 1)
        XCTAssertEqual(hosting.bounds.width, 360, accuracy: 0.5)
        try self.drag(in: window, from: dragStart, deltaY: -80)
        XCTAssertEqual(layout.resolvedPanelHeight, 560, accuracy: 1)
        XCTAssertEqual(hosting.bounds.height, 560, accuracy: 1)
        XCTAssertEqual(window.frame.maxY, windowTop, accuracy: 0.5)
        try self.drag(in: window, from: dragStart, deltaY: -200)
        XCTAssertEqual(layout.resolvedPanelHeight, 640, accuracy: 1)
        try self.drag(in: window, from: NSPoint(x: 338, y: 12), deltaY: 500)
        XCTAssertGreaterThanOrEqual(layout.resolvedPanelHeight, layout.minPanelHeight)
        XCTAssertLessThan(layout.resolvedPanelHeight, 480)
        XCTAssertEqual(hosting.bounds.width, 360, accuracy: 0.5)

        XCTAssertNil(model.apiClient)
        XCTAssertFalse(model.processManager.isRunning)
    }

    @MainActor
    private func contentScrollView(in view: NSView) throws -> NSScrollView {
        func descendants(_ node: NSView) -> [NSScrollView] {
            let own = (node as? NSScrollView).map { [$0] } ?? []
            return own + node.subviews.flatMap(descendants)
        }
        let scrolls = descendants(view).filter { !$0.isHidden && $0.bounds.height > 50 }
        XCTAssertEqual(scrolls.count, 1)
        return try XCTUnwrap(scrolls.first)
    }

    @MainActor
    private func drag(in window: NSWindow, from start: NSPoint, deltaY: CGFloat, deltaX: CGFloat = 0) throws {
        let screenStart = window.convertPoint(toScreen: start)
        let end = NSPoint(x: screenStart.x + deltaX, y: screenStart.y + deltaY)
        let events: [(NSEvent.EventType, NSPoint)] = [
            (.leftMouseDown, screenStart), (.leftMouseDragged, end), (.leftMouseUp, end),
        ]
        for (index, event) in events.enumerated() {
            let mouse = try XCTUnwrap(NSEvent.mouseEvent(
                with: event.0, location: window.convertPoint(fromScreen: event.1), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 100 + index, clickCount: 1, pressure: 1))
            NSApplication.shared.sendEvent(mouse)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }
}
