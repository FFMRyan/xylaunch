import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreGraphics

struct LauncherRootView: View {
    @ObservedObject var viewModel: LauncherViewModel

    @State private var isShowingURLSheet = false
    @State private var urlInput = ""
    @State private var hoveredID: String?
    @State private var currentPage = 0
    @State private var contentSafeInsets = EdgeInsets()
    @State private var isShowingSystemFolder = false
    @State private var activeDragToken: String?
    @State private var layout = LauncherLayout.default
    @GestureState private var dragOffsetX: CGFloat = 0

    private let maxColumnCount = 7
    private let maxRowCount = 5
    private let pageSwipeThreshold: CGFloat = 120
    private let pageSpacing: CGFloat = 48
    private let topGapToGrid: CGFloat = 52
    private let gridBottomGap: CGFloat = 20
    private let searchTopGap: CGFloat = 28
    private let dotsBottomGap: CGFloat = 34
    private let searchBarHeight: CGFloat = 34
    private let baseVerticalPadding: CGFloat = 40
    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(layout.tileWidth), spacing: layout.columnSpacing),
            count: layout.columnCount
        )
    }
    private var pageItemCount: Int {
        max(1, layout.columnCount * layout.rowCount)
    }
    private var gridWidth: CGFloat {
        CGFloat(layout.columnCount) * layout.tileWidth
            + CGFloat(layout.columnCount - 1) * layout.columnSpacing
    }
    private var pageStrideWidth: CGFloat {
        gridWidth + pageSpacing
    }
    private var searchQuery: String {
        viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var hasSearchQuery: Bool {
        !searchQuery.isEmpty
    }
    private var isInAggregateFolderView: Bool {
        isShowingSystemFolder && !hasSearchQuery
    }

    var body: some View {
        ZStack {
            backgroundLayer
                .contentShape(Rectangle())
                .onTapGesture {
                    if isInAggregateFolderView {
                        closeAggregateFolder()
                    } else {
                        viewModel.requestClosePanel()
                    }
                }
            centeredContent
            .padding(.top, contentSafeInsets.top)
            .padding(.bottom, contentSafeInsets.bottom)
            .padding(.leading, contentSafeInsets.leading)
            .padding(.trailing, contentSafeInsets.trailing)
            if isInAggregateFolderView {
                aggregateFolderOverlay
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.92).combined(with: .opacity),
                            removal: .scale(scale: 0.96).combined(with: .opacity)
                        )
                    )
                    .zIndex(5)
            }
        }
        .background(
            TrackpadSwipeMonitor { direction in
                handlePageSwipe(direction)
            }
        )
        .background(
            VisibleFrameInsetReader { newInsets in
                guard !approximatelyEqual(contentSafeInsets, newInsets) else {
                    return
                }
                DispatchQueue.main.async {
                    if !approximatelyEqual(contentSafeInsets, newInsets) {
                        contentSafeInsets = newInsets
                    }
                }
            }
        )
        .onExitCommand {
            if isInAggregateFolderView {
                closeAggregateFolder()
            } else {
                viewModel.requestClosePanel()
            }
        }
        .sheet(isPresented: $isShowingURLSheet) {
            addURLSheet
        }
        .onChange(of: displayItemIDs) { _ in
            currentPage = 0
        }
        .onChange(of: hasSearchQuery) { searching in
            if searching && isShowingSystemFolder {
                isShowingSystemFolder = false
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: isInAggregateFolderView)
    }

    private var centeredContent: some View {
        GeometryReader { proxy in
            let scale = contentScale(in: proxy.size, contentHeight: contentHeight)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 0) {
                    if !isInAggregateFolderView {
                        searchBar
                            .padding(.top, searchTopGap)
                    }

                    if hasSearchQuery {
                        HStack {
                            Text("搜索结果：\(displayItems.count)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.88))
                            Spacer()
                        }
                        .frame(width: gridWidth)
                        .padding(.top, 10)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        errorBanner(errorMessage)
                            .padding(.horizontal, 30)
                            .padding(.top, 12)
                    }

                    launcherGridContent

                    paginationDots
                        .padding(.top, 8)
                }
                .scaleEffect(scale, anchor: .center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, layout.horizontalInset)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isInAggregateFolderView, activeDragToken == nil else {
                        return
                    }
                    viewModel.requestClosePanel()
                }
                .onAppear {
                    updateLayout(for: proxy.size)
                }
                .onChange(of: proxy.size) { newSize in
                    updateLayout(for: newSize)
                }
                .onChange(of: contentSafeInsets) { _ in
                    updateLayout(for: proxy.size)
                }

                Spacer(minLength: 0)
                    .frame(minHeight: dotsBottomGap)
            }
        }
    }

    @ViewBuilder
    private var launcherGridContent: some View {
        if displayItems.isEmpty {
            emptySearchState
                .frame(width: gridWidth)
                .frame(height: currentGridHeight)
                .padding(.top, topGapToGrid)
        } else {
            let pages = pagedItems
            ZStack {
                // Catch taps on blank grid area and close launcher.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isInAggregateFolderView, activeDragToken == nil else {
                            return
                        }
                        viewModel.requestClosePanel()
                    }

                Group {
                    HStack(spacing: pageSpacing) {
                        ForEach(pages.indices, id: \.self) { index in
                            LazyVGrid(columns: columns, spacing: layout.rowSpacing) {
                                ForEach(pages[index]) { item in
                                    launchTile(item)
                                }
                            }
                            .frame(width: gridWidth, height: currentGridHeight, alignment: .top)
                        }
                    }
                    .frame(width: gridWidth, height: currentGridHeight, alignment: .leading)
                    .offset(x: -CGFloat(currentPage) * pageStrideWidth + dragOffsetX)
                    .clipped()
                }
            }
            .frame(width: gridWidth, height: currentGridHeight, alignment: .leading)
            .padding(.top, topGapToGrid)
            .padding(.bottom, gridBottomGap)
            .contentShape(Rectangle())
            .simultaneousGesture(pageSwipeGesture)
            .opacity(isInAggregateFolderView ? 0 : 1)
            .allowsHitTesting(!isInAggregateFolderView)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.85), value: currentPage)
            .animation(.easeOut(duration: 0.15), value: viewModel.searchText)
            .animation(.easeOut(duration: 0.2), value: isInAggregateFolderView)
        }
    }

    private var aggregateFolderOverlay: some View {
        GeometryReader { proxy in
            let panelWidth = min(proxy.size.width * 0.94, gridWidth + 160)
            let panelHeight = min(proxy.size.height * 0.84, currentGridHeight + 280)

            ZStack {
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeAggregateFolder()
                    }
                    .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
                        handlePromoteDrop(providers)
                    }

                VStack(spacing: 14) {
                    Text("其他")
                        .font(.system(size: 25, weight: .regular))
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.top, -6)

                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(Color.white.opacity(0.19))
                        .overlay(
                            RoundedRectangle(cornerRadius: 34, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                        .overlay(
                            ScrollView(.vertical, showsIndicators: false) {
                                LazyVGrid(columns: columns, spacing: layout.rowSpacing) {
                                    ForEach(groupedSystemApps, id: \.id) { app in
                                        folderAppTile(app)
                                    }
                                }
                                .padding(.horizontal, 30)
                                .padding(.top, 26)
                                .padding(.bottom, 32)
                            }
                        )
                        .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 10)
                        .frame(width: panelWidth, height: panelHeight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func folderAppTile(_ app: ApplicationEntry) -> some View {
        LaunchPadTile(
            title: app.name,
            icon: viewModel.icon(for: app),
            previewIcons: [],
            tileWidth: layout.tileWidth,
            tileHeight: layout.tileHeight,
            iconSize: layout.iconSize,
            isHovered: hoveredID == app.id
        ) {
            viewModel.open(app)
        }
        .onHover { hovering in
            hoveredID = hovering ? app.id : nil
        }
        .onDrag {
            NSItemProvider(object: "promote:\(app.path)" as NSString)
        }
    }

    private var currentGridRows: Int {
        layout.rowCount
    }

    private var currentGridHeight: CGFloat {
        CGFloat(currentGridRows) * layout.tileHeight
            + CGFloat(max(0, currentGridRows - 1)) * layout.rowSpacing
    }

    private var contentHeight: CGFloat {
        searchTopGap + searchBarHeight + topGapToGrid + currentGridHeight + gridBottomGap + dotsBottomGap + 28
    }

    private func contentScale(in size: CGSize, contentHeight: CGFloat) -> CGFloat {
        let horizontalPadding: CGFloat = layout.horizontalInset * 2
        let verticalPadding = baseVerticalPadding
        let widthScale = max(0.1, (size.width - horizontalPadding) / gridWidth)
        let heightScale = max(0.1, (size.height - verticalPadding) / contentHeight)
        return min(1.15, widthScale, heightScale)
    }

    private func launchTile(_ item: LaunchDisplayItem) -> some View {
        LaunchPadTile(
            title: item.title,
            icon: item.icon,
            previewIcons: item.previewIcons,
            tileWidth: layout.tileWidth,
            tileHeight: layout.tileHeight,
            iconSize: layout.iconSize,
            isHovered: hoveredID == item.id
        ) {
            item.action()
        }
        .onHover { hovering in
            hoveredID = hovering ? item.id : nil
        }
        .opacity(activeDragToken == item.dragToken ? 0.0 : 1.0)
        .animation(.interactiveSpring(response: 0.26, dampingFraction: 0.84), value: activeDragToken)
        .contextMenu {
            if let pinned = item.pinnedItem {
                Button("移除固定") {
                    viewModel.removePinned(pinned)
                }
            }
        }
        .modifier(ReorderModifier(item: item, onDropToken: { token, target in
            handleReorder(from: token, to: target)
        }, activeDragToken: $activeDragToken))
    }

    private func approximatelyEqual(_ lhs: EdgeInsets, _ rhs: EdgeInsets) -> Bool {
        let threshold: CGFloat = 0.5
        return abs(lhs.top - rhs.top) < threshold
            && abs(lhs.bottom - rhs.bottom) < threshold
            && abs(lhs.leading - rhs.leading) < threshold
            && abs(lhs.trailing - rhs.trailing) < threshold
    }

    private func updateLayout(for size: CGSize) {
        let next = LauncherLayout.compute(
            for: size,
            safeInsets: contentSafeInsets,
            maxColumns: maxColumnCount,
            maxRows: maxRowCount
        )
        guard next != layout else {
            return
        }

        layout = next
        let totalPages = max(1, Int(ceil(Double(displayItems.count) / Double(pageItemCount))))
        currentPage = min(currentPage, totalPages - 1)
    }

    private var backgroundLayer: some View {
        ZStack {
            VisualBlurBackground()
                .ignoresSafeArea()

            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.03, green: 0.37, blue: 0.63).opacity(0.74), location: 0),
                    .init(color: Color(red: 0.05, green: 0.50, blue: 0.67).opacity(0.62), location: 0.4),
                    .init(color: Color(red: 0.24, green: 0.48, blue: 0.44).opacity(0.56), location: 1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(.white.opacity(0.16))
                .frame(width: 330)
                .blur(radius: 50)
                .offset(x: 110, y: 230)
            Circle()
                .fill(Color(red: 0.2, green: 0.95, blue: 0.8).opacity(0.2))
                .frame(width: 410)
                .blur(radius: 55)
                .offset(x: -330, y: 250)
            Circle()
                .fill(Color(red: 0.02, green: 0.14, blue: 0.31).opacity(0.3))
                .frame(width: 550)
                .blur(radius: 80)
                .offset(x: 250, y: -190)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.82))
            TextField("搜索", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
        }
        .font(.system(size: 17, weight: .regular, design: .rounded))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(width: layout.searchBarWidth)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        )
        .padding(.horizontal, 18)
    }

    private var emptySearchState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
            Text("未找到匹配应用")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
            Text("请尝试其他关键词")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.78))
        }
    }

    private var pinnedApps: [LaunchItem] {
        viewModel.filteredPinnedItems.filter { $0.kind == .app }
    }

    private var pinnedAppPaths: Set<String> {
        Set(pinnedApps.map(\.rawValue))
    }

    private var nonPinnedApps: [ApplicationEntry] {
        viewModel.filteredApplications.filter { !pinnedAppPaths.contains($0.path) }
    }

    private var groupedSystemApps: [ApplicationEntry] {
        nonPinnedApps.filter { app in
            isAppleCreatedApplication(app) && !viewModel.isPromotedAppleApplication(path: app.path)
        }
    }

    private var regularApps: [ApplicationEntry] {
        nonPinnedApps.filter { app in
            !isAppleCreatedApplication(app) || viewModel.isPromotedAppleApplication(path: app.path)
        }
    }

    private var displayItems: [LaunchDisplayItem] {
        var items: [LaunchDisplayItem] = []
        for item in pinnedApps {
            items.append(
                LaunchDisplayItem(
                    id: item.id.uuidString,
                    title: item.name,
                    icon: viewModel.icon(for: item),
                    previewIcons: [],
                    pinnedItem: item,
                    reorderTarget: .pinned(item.id),
                    action: { viewModel.open(item) }
                )
            )
        }

        let visibleApps: [ApplicationEntry]
        if hasSearchQuery {
            visibleApps = nonPinnedApps
        } else {
            visibleApps = regularApps
        }

        for app in visibleApps {
            items.append(
                LaunchDisplayItem(
                    id: app.id,
                    title: app.name,
                    icon: viewModel.icon(for: app),
                    previewIcons: [],
                    pinnedItem: nil,
                    reorderTarget: .application(app.path),
                    action: { viewModel.open(app) }
                )
            )
        }

        if !hasSearchQuery, !groupedSystemApps.isEmpty {
            items.append(
                LaunchDisplayItem(
                    id: "system-folder",
                    title: "其他",
                    icon: folderIcon,
                    previewIcons: groupedSystemApps.prefix(9).map { viewModel.icon(for: $0) },
                    pinnedItem: nil,
                    reorderTarget: .none,
                    action: {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                            isShowingSystemFolder = true
                        }
                    }
                )
            )
        }
        return items
    }

    private var folderIcon: NSImage {
        NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "系统文件夹") ?? NSImage()
    }

    private func isAppleCreatedApplication(_ app: ApplicationEntry) -> Bool {
        if let bundleIdentifier = app.bundleIdentifier?.lowercased(),
           bundleIdentifier.hasPrefix("com.apple.") {
            return true
        }
        return false
    }

    private func closeAggregateFolder() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            isShowingSystemFolder = false
        }
    }

    private func handlePromoteDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }) else {
            return false
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
            guard
                let data,
                let token = String(data: data, encoding: .utf8),
                token.hasPrefix("promote:")
            else {
                return
            }

            let path = String(token.dropFirst("promote:".count))
            DispatchQueue.main.async {
                self.viewModel.promoteAppleApplicationToTopLevel(path: path)
                self.closeAggregateFolder()
            }
        }
        return true
    }

    private var displayItemIDs: [String] {
        displayItems.map(\.id)
    }

    private var pagedItems: [[LaunchDisplayItem]] {
        let items = displayItems
        guard !items.isEmpty else {
            return [[]]
        }
        return stride(from: 0, to: items.count, by: pageItemCount).map { offset in
            Array(items[offset ..< min(offset + pageItemCount, items.count)])
        }
    }

    private var paginationDots: some View {
        let totalPages = pagedItems.count
        return Group {
            if totalPages > 1 {
                HStack(spacing: 10) {
                    ForEach(0 ..< totalPages, id: \.self) { index in
                        Button {
                            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.85)) {
                                currentPage = index
                            }
                        } label: {
                            Circle()
                                .fill(.white.opacity(index == currentPage ? 0.95 : 0.45))
                                .frame(width: 10, height: 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var pageSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .updating($dragOffsetX) { value, state, _ in
                let totalPages = pagedItems.count
                guard totalPages > 1 else {
                    state = 0
                    return
                }
                let translation = value.translation.width
                let isAtLeftEdge = currentPage == 0 && translation > 0
                let isAtRightEdge = currentPage == totalPages - 1 && translation < 0
                state = (isAtLeftEdge || isAtRightEdge) ? translation * 0.3 : translation
            }
            .onEnded { value in
                let horizontal = value.translation.width
                guard abs(horizontal) >= pageSwipeThreshold else {
                    return
                }
                handlePageSwipe(horizontal < 0 ? .left : .right)
            }
    }

    private func handlePageSwipe(_ direction: HorizontalPageSwipeDirection) {
        guard !isInAggregateFolderView else {
            return
        }
        let totalPages = pagedItems.count
        guard totalPages > 1 else {
            return
        }

        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.85)) {
            switch direction {
            case .left:
                currentPage = min(currentPage + 1, totalPages - 1)
            case .right:
                currentPage = max(currentPage - 1, 0)
            }
        }
    }

    private func handleReorder(from dragToken: String, to target: LaunchDisplayItem) -> Bool {
        let source = parseDragToken(dragToken)
        switch (source, target.reorderTarget) {
        case let (.pinned(sourceID), .pinned(targetID)):
            viewModel.movePinnedItem(withId: sourceID, before: targetID)
            return true
        case let (.application(sourcePath), .application(targetPath)):
            viewModel.moveApplication(path: sourcePath, before: targetPath)
            return true
        default:
            return false
        }
    }

    private func parseDragToken(_ token: String) -> ReorderTarget {
        if token.hasPrefix("pinned:") {
            let value = String(token.dropFirst("pinned:".count))
            if let id = UUID(uuidString: value) {
                return .pinned(id)
            }
        } else if token.hasPrefix("app:") {
            let value = String(token.dropFirst("app:".count))
            return .application(value)
        }
        return .none
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .lineLimit(2)
            Spacer()
            Button("关闭") {
                viewModel.clearErrorMessage()
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 13, weight: .medium))
        .padding(10)
        .foregroundStyle(.white)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.72, green: 0.29, blue: 0.19).opacity(0.85))
        )
    }

    private var addURLSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("添加网址")
                .font(.headline)
            TextField("例如: github.com", text: $urlInput)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消") {
                    urlInput = ""
                    isShowingURLSheet = false
                }
                Button("添加") {
                    viewModel.addPinnedURL(from: urlInput)
                    urlInput = ""
                    isShowingURLSheet = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

private struct VisualBlurBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.state = .active
    }
}

private struct VisibleFrameInsetReader: NSViewRepresentable {
    let onChange: (EdgeInsets) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeNSView(context: Context) -> InsetObserverView {
        let view = InsetObserverView()
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(window: window)
        }
        context.coordinator.updateInsets(for: view.window)
        return view
    }

    func updateNSView(_ nsView: InsetObserverView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.attach(window: nsView.window)
        context.coordinator.updateInsets(for: nsView.window)
    }

    static func dismantleNSView(_ nsView: InsetObserverView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject {
        var onChange: (EdgeInsets) -> Void
        private weak var observedWindow: NSWindow?

        init(onChange: @escaping (EdgeInsets) -> Void) {
            self.onChange = onChange
            super.init()
        }

        func attach(window: NSWindow?) {
            guard observedWindow !== window else {
                return
            }

            detach()
            observedWindow = window

            let center = NotificationCenter.default
            if let window {
                center.addObserver(self, selector: #selector(handleWindowEvent(_:)), name: NSWindow.didResizeNotification, object: window)
                center.addObserver(self, selector: #selector(handleWindowEvent(_:)), name: NSWindow.didMoveNotification, object: window)
                center.addObserver(self, selector: #selector(handleWindowEvent(_:)), name: NSWindow.didChangeScreenNotification, object: window)
            }

            center.addObserver(self, selector: #selector(handleWindowEvent(_:)), name: NSApplication.didChangeScreenParametersNotification, object: nil)

            updateInsets(for: window)
        }

        func detach() {
            let center = NotificationCenter.default
            center.removeObserver(self)
            observedWindow = nil
        }

        @objc private func handleWindowEvent(_ notification: Notification) {
            updateInsets(for: observedWindow)
        }

        func updateInsets(for window: NSWindow?) {
            let screen = window?.screen ?? NSScreen.main
            guard let screen else {
                onChange(EdgeInsets())
                return
            }

            let frame = screen.frame
            let visible = screen.visibleFrame

            let insets = EdgeInsets(
                top: max(0, frame.maxY - visible.maxY),
                leading: max(0, visible.minX - frame.minX),
                bottom: max(0, visible.minY - frame.minY),
                trailing: max(0, frame.maxX - visible.maxX)
            )

            onChange(insets)
        }
    }
}

private final class InsetObserverView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}

private struct LaunchDisplayItem: Identifiable {
    let id: String
    let title: String
    let icon: NSImage
    let previewIcons: [NSImage]
    let pinnedItem: LaunchItem?
    let reorderTarget: ReorderTarget
    let action: () -> Void

    var dragToken: String {
        switch reorderTarget {
        case let .pinned(id):
            return "pinned:\(id.uuidString)"
        case let .application(path):
            return "app:\(path)"
        case .none:
            return "none:\(id)"
        }
    }
}

private struct ReorderModifier: ViewModifier {
    let item: LaunchDisplayItem
    let onDropToken: (String, LaunchDisplayItem) -> Bool
    @Binding var activeDragToken: String?

    func body(content: Content) -> some View {
        if case .none = item.reorderTarget {
            content
        } else {
            content
                .onDrag {
                    activeDragToken = item.dragToken
                    return NSItemProvider(object: item.dragToken as NSString)
                }
                .onDrop(
                    of: [UTType.plainText],
                    delegate: LaunchItemDropDelegate(
                        target: item,
                        onDropToken: onDropToken,
                        activeDragToken: $activeDragToken
                    )
                )
        }
    }
}

private enum HorizontalPageSwipeDirection {
    case left
    case right
}

private enum ReorderTarget {
    case pinned(UUID)
    case application(String)
    case none
}

private struct LaunchItemDropDelegate: DropDelegate {
    let target: LaunchDisplayItem
    let onDropToken: (String, LaunchDisplayItem) -> Bool
    @Binding var activeDragToken: String?

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.plainText])
    }

    func dropEntered(info: DropInfo) {
        guard let token = activeDragToken else {
            return
        }
        withAnimation(.interactiveSpring(response: 0.26, dampingFraction: 0.84)) {
            _ = onDropToken(token, target)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        // Keep dragging state only while pointer is in a drop target region.
        if activeDragToken == target.dragToken {
            activeDragToken = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { activeDragToken = nil }

        if let token = activeDragToken {
            withAnimation(.interactiveSpring(response: 0.26, dampingFraction: 0.84)) {
                _ = onDropToken(token, target)
            }
            return true
        }

        guard
            let provider = info.itemProviders(for: [UTType.plainText]).first
        else {
            return false
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
            guard
                let data,
                let token = String(data: data, encoding: .utf8)
            else {
                return
            }

            DispatchQueue.main.async {
                _ = onDropToken(token, target)
            }
        }
        return true
    }
}

private struct TrackpadSwipeMonitor: NSViewRepresentable {
    let onSwipe: (HorizontalPageSwipeDirection) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSwipe: onSwipe)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.start()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onSwipe = onSwipe
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var onSwipe: (HorizontalPageSwipeDirection) -> Void
        private var monitorToken: Any?
        private var accumulatedX: CGFloat = 0
        private let threshold: CGFloat = 38
        private var hasTriggeredInCurrentGesture = false

        init(onSwipe: @escaping (HorizontalPageSwipeDirection) -> Void) {
            self.onSwipe = onSwipe
        }

        func start() {
            guard monitorToken == nil else {
                return
            }

            monitorToken = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func stop() {
            if let monitorToken {
                NSEvent.removeMonitor(monitorToken)
                self.monitorToken = nil
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY

            if event.phase == .began {
                accumulatedX = 0
                hasTriggeredInCurrentGesture = false
            }

            guard abs(dx) > abs(dy), abs(dx) > 0.5 else {
                resetIfEnded(event)
                return event
            }

            accumulatedX += dx

            guard !hasTriggeredInCurrentGesture else {
                resetIfEnded(event)
                return nil
            }

            if abs(accumulatedX) >= threshold {
                let direction: HorizontalPageSwipeDirection = accumulatedX < 0 ? .left : .right
                onSwipe(direction)
                accumulatedX = 0
                hasTriggeredInCurrentGesture = true
                return nil
            }

            resetIfEnded(event)
            return event
        }

        private func resetIfEnded(_ event: NSEvent) {
            if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
                accumulatedX = 0
                hasTriggeredInCurrentGesture = false
            }
        }
    }
}

private struct LaunchPadTile: View {
    let title: String
    let icon: NSImage
    let previewIcons: [NSImage]
    let tileWidth: CGFloat
    let tileHeight: CGFloat
    let iconSize: CGFloat
    let isHovered: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                if previewIcons.isEmpty {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: iconSize, height: iconSize)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 6)
                } else {
                    FolderPreviewIcon(
                        icons: previewIcons,
                        size: iconSize
                    )
                    .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 6)
                }
                Text(title)
                    .font(.system(size: 37 / 3, weight: .regular, design: .rounded))
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.95))
            }
            .frame(width: tileWidth, height: tileHeight)
            .scaleEffect(isHovered ? 1.04 : 1.0)
            .animation(.easeOut(duration: 0.18), value: isHovered)
        }
        .buttonStyle(.plain)
    }
}

private struct FolderPreviewIcon: View {
    let icons: [NSImage]
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.52),
                            Color.white.opacity(0.3),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(size * 0.18), spacing: size * 0.04), count: 3),
                spacing: size * 0.04
            ) {
                ForEach(Array(icons.prefix(9).enumerated()), id: \.offset) { _, icon in
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: size * 0.18, height: size * 0.18)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.04, style: .continuous))
                }
            }
            .padding(size * 0.14)
        }
        .frame(width: size, height: size)
    }
}

private struct LauncherLayout: Equatable {
    let columnCount: Int
    let rowCount: Int
    let tileWidth: CGFloat
    let tileHeight: CGFloat
    let columnSpacing: CGFloat
    let rowSpacing: CGFloat
    let horizontalInset: CGFloat
    let searchBarWidth: CGFloat

    var iconSize: CGFloat {
        max(76, min(160, tileWidth * 0.73))
    }

    static let `default` = LauncherLayout(
        columnCount: 7,
        rowCount: 5,
        tileWidth: 174,
        tileHeight: 202,
        columnSpacing: 44,
        rowSpacing: 36,
        horizontalInset: 150,
        searchBarWidth: 396
    )

    static func compute(
        for size: CGSize,
        safeInsets: EdgeInsets,
        maxColumns: Int,
        maxRows: Int
    ) -> LauncherLayout {
        let availableWidth = max(420, size.width - safeInsets.leading - safeInsets.trailing - 48)
        let horizontalInset = max(20, min(130, availableWidth * 0.08))
        let gridContainerWidth = max(300, availableWidth - horizontalInset * 2)

        let minTileWidth: CGFloat = 112
        let maxTileWidth: CGFloat = 220
        let minColumnSpacing: CGFloat = 18
        let maxColumnSpacing: CGFloat = 44

        var columnCount = Int((gridContainerWidth + minColumnSpacing) / (minTileWidth + minColumnSpacing))
        columnCount = max(2, min(maxColumns, columnCount))

        let spacingDenominator = CGFloat(max(1, columnCount - 1))
        let preferredSpacing = (gridContainerWidth - CGFloat(columnCount) * minTileWidth) / spacingDenominator
        let columnSpacing = max(minColumnSpacing, min(maxColumnSpacing, preferredSpacing))
        let tileWidth = min(
            maxTileWidth,
            max(
                minTileWidth,
                (gridContainerWidth - CGFloat(columnCount - 1) * columnSpacing) / CGFloat(columnCount)
            )
        )

        let tileHeight = tileWidth * (202.0 / 174.0)
        let rowSpacing = max(16, min(36, columnSpacing * 0.82))

        let availableHeight = max(380, size.height - safeInsets.top - safeInsets.bottom)
        let reservedHeight: CGFloat = 28 + 34 + 52 + 20 + 34 + 28 + 40
        let gridBudget = max(tileHeight * 2 + rowSpacing, availableHeight - reservedHeight)
        var rowCount = Int((gridBudget + rowSpacing) / (tileHeight + rowSpacing))
        rowCount = max(2, min(maxRows, rowCount))

        let searchBarWidth = max(260, min(520, gridContainerWidth * 0.46))

        return LauncherLayout(
            columnCount: columnCount,
            rowCount: rowCount,
            tileWidth: tileWidth,
            tileHeight: tileHeight,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing,
            horizontalInset: horizontalInset,
            searchBarWidth: searchBarWidth
        )
    }
}

private struct LaunchPadToolButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(configuration.isPressed ? 0.18 : 0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.25), lineWidth: 1)
            )
    }
}
