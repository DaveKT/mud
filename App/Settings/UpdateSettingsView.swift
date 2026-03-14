#if SPARKLE
import SwiftUI
import Sparkle

struct UpdateSettingsView: View {
    @AppStorage("SUEnableAutomaticChecks") private var autoCheck = true
    @AppStorage("SUAutomaticallyUpdate") private var autoInstall = false

    var body: some View {
        Form {
            Toggle("Automatically check for updates", isOn: $autoCheck)
            Toggle("Automatically install updates", isOn: $autoInstall)
                .disabled(!autoCheck)

            Button("Check Now") {
                SparkleController.updater.checkForUpdates()
            }
        }
        .formStyle(.grouped)
        .padding(.top, -18)
    }
}
#endif
