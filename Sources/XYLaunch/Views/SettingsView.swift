import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: LauncherViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("XYLaunch")
                .font(.title2.bold())
            Text("你的状态栏启动台已启动。")
                .foregroundStyle(.secondary)

            Divider()

            Label("快捷键：Command + Option + Space", systemImage: "keyboard")
            Label("左键点击状态栏图标可打开启动台", systemImage: "menubar.rectangle")
            Label("右键点击状态栏图标可打开快捷菜单", systemImage: "cursorarrow.click.2")

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
    }
}
