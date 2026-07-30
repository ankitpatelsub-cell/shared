import SwiftUI

struct AboutView: View {
    var body: some View {
        List {
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
