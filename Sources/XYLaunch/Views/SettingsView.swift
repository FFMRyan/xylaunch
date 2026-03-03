import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: LauncherViewModel
    @State private var launchAtLoginEnabled = LaunchAtLoginManager.shared.isEnabled
    @State private var launchErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("小火箭启动器")
                .font(.title2.bold())
            Text("你的状态栏启动台已启动。")
                .foregroundStyle(.secondary)

            Divider()

            Label("快捷键：Command + Option + Space", systemImage: "keyboard")
            Label("左键点击状态栏图标可打开启动台", systemImage: "menubar.rectangle")
            Label("右键点击状态栏图标可打开快捷菜单", systemImage: "cursorarrow.click.2")

            if LaunchAtLoginManager.shared.isSupported {
                Toggle("开机自动启动", isOn: $launchAtLoginEnabled)
                    .onChange(of: launchAtLoginEnabled) { enabled in
                        do {
                            try LaunchAtLoginManager.shared.setEnabled(enabled)
                            launchErrorMessage = nil
                        } catch {
                            launchAtLoginEnabled = LaunchAtLoginManager.shared.isEnabled
                            launchErrorMessage = "开机启动设置失败：\(error.localizedDescription)"
                        }
                    }
            }

            if let launchErrorMessage {
                Text(launchErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            HStack {
                Text("固定项目：\(viewModel.pinnedItems.count)")
                Spacer()
                Button("刷新应用列表") {
                    viewModel.refreshApplications()
                }
            }
        }
        .padding(20)
        .onAppear {
            launchAtLoginEnabled = LaunchAtLoginManager.shared.isEnabled
        }
    }
}
