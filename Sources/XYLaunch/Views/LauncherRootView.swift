import SwiftUI

struct LauncherRootView: View {
    @ObservedObject var viewModel: LauncherViewModel

    @State private var isShowingURLSheet = false
    @State private var urlInput = ""

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.16, blue: 0.24),
                    Color(red: 0.06, green: 0.08, blue: 0.12),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                header
                tabPicker
                if let errorMessage = viewModel.errorMessage {
                    errorBanner(errorMessage)
                }
                content
            }
            .padding(24)
        }
        .onExitCommand {
            viewModel.requestClosePanel()
        }
        .sheet(isPresented: $isShowingURLSheet) {
            addURLSheet
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("XYLaunch")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text("状态栏启动台")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer(minLength: 16)

            if viewModel.isScanning {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }

            TextField("搜索应用、文件夹、网址", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)

            Button("添加文件/应用") {
                viewModel.addPinnedByOpenPanel()
            }

            Button("添加网址") {
                isShowingURLSheet = true
            }

            Button("刷新") {
                viewModel.refreshApplications()
            }
        }
        .foregroundStyle(.white)
    }

    private var tabPicker: some View {
        Picker("分类", selection: $viewModel.selectedTab) {
            ForEach(LauncherTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if shouldShowApplications {
                    appSection
                }
                if shouldShowPinned {
                    pinnedSection
                    pinnedManageSection
                }
            }
        }
    }

    private var shouldShowApplications: Bool {
        viewModel.selectedTab == .all || viewModel.selectedTab == .applications
    }

    private var shouldShowPinned: Bool {
        viewModel.selectedTab == .all || viewModel.selectedTab == .pinned
    }

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("应用库")

            if viewModel.filteredApplications.isEmpty {
                sectionPlaceholder("未找到匹配应用")
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(viewModel.filteredApplications) { app in
                        LaunchTile(
                            title: app.name,
                            subtitle: "应用",
                            icon: viewModel.icon(for: app)
                        ) {
                            viewModel.open(app)
                        }
                    }
                }
            }
        }
    }

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("固定项目")

            if viewModel.filteredPinnedItems.isEmpty {
                sectionPlaceholder("还没有固定项目")
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(viewModel.filteredPinnedItems) { item in
                        LaunchTile(
                            title: item.name,
                            subtitle: item.kind.title,
                            icon: viewModel.icon(for: item)
                        ) {
                            viewModel.open(item)
                        }
                        .contextMenu {
                            Button("移除固定") {
                                viewModel.removePinned(item)
                            }
                        }
                    }
                }
            }
        }
    }

    private var pinnedManageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("固定项管理")
                Spacer()
                Text("上移 / 下移 / 删除")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }

            VStack(spacing: 8) {
                ForEach(Array(viewModel.pinnedItems.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 10) {
                        Image(nsImage: viewModel.icon(for: item))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                        Text(item.name)
                            .lineLimit(1)
                            .foregroundStyle(.white)
                        Spacer()
                        Text(item.kind.title)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                        Button {
                            viewModel.movePinnedUp(item)
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)

                        Button {
                            viewModel.movePinnedDown(item)
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == viewModel.pinnedItems.count - 1)

                        Button(role: .destructive) {
                            viewModel.removePinned(item)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.white.opacity(0.08))
                    )
                }
            }
            .frame(minHeight: 120, maxHeight: 200)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.thinMaterial.opacity(0.45))
            )
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
    }

    private func sectionPlaceholder(_ text: String) -> some View {
        HStack {
            Spacer()
            Text(text)
                .foregroundStyle(.white.opacity(0.65))
            Spacer()
        }
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.45))
        )
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

private struct LaunchTile: View {
    let title: String
    let subtitle: String
    let icon: NSImage
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity, minHeight: 110)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.58))
            )
        }
        .buttonStyle(.plain)
    }
}
