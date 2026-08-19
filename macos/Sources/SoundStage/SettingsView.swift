import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { model.loginItem.isOn },
                    set: { model.setOpenAtLogin($0) }
                ))
                .disabled(!model.loginItem.isInteractive)
                Text(model.loginItem.caption)
                    .font(.caption)
                    .foregroundStyle(CaptureTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.loginItem.showsSystemSettingsLink {
                    Button("Open Login Items…") {
                        model.openLoginItemsSettings()
                    }
                }
            } header: {
                Text("Startup")
            }

            Section {
                Button("Menu Bar Settings…") {
                    AppDelegate.openMenuBarSettings()
                }
            } header: {
                Text("Menu bar")
            } footer: {
                Text("If the SoundStage item is missing from the menu bar, turn it on here.")
                    .font(.caption)
            }

            if let error = model.errorMessage {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshLoginItem() }
    }
}
