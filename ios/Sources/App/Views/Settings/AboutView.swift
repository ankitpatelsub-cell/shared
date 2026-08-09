import SwiftUI

struct AboutView: View {
    private var versionString: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(shortVersion) (\(build))"
    }

    var body: some View {
        List {
            // The build number now tracks the CI run that produced this
            // IPA (was previously a hardcoded "2" that never changed,
            // making it impossible to tell from a crash report alone
            // whether it came from an old or already-fixed build).
            Section {
                LabeledContent("Version", value: versionString)
            }
            Section("Open Source Licenses") {
                LicenseRow(name: "SwiftTerm", license: "MIT", url: "https://github.com/migueldeicaza/SwiftTerm")
                LicenseRow(name: "Citadel", license: "Apache 2.0", url: "https://github.com/orlandos-nl/Citadel")
            }
            Section {
                Text("TermVault is original code and assets, inspired by the layout and workflow of existing SSH clients — not copied from them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("About")
    }
}

private struct LicenseRow: View {
    let name: String
    let license: String
    let url: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(name).font(.body)
            Text(license).font(.caption).foregroundStyle(.secondary)
            Text(url).font(.caption2).foregroundStyle(.tint)
        }
    }
}
