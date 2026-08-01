import Foundation

struct SSHConfigHost {
    var alias: String
    var hostname: String
    var user: String
    var port: Int
    var proxyJump: String?
}

enum SSHConfigService {
    static func parse(_ text: String) -> [SSHConfigHost] {
        var result: [SSHConfigHost] = []
        var current: SSHConfigHost?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.split(separator: "#", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let parts = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased(), value = parts[1].trimmingCharacters(in: .whitespaces)
            if key == "host" {
                if let current, !current.alias.contains("*") { result.append(current) }
                current = SSHConfigHost(alias: value, hostname: value, user: "root", port: 22)
            } else if current != nil {
                switch key {
                case "hostname": current?.hostname = value
                case "user": current?.user = value
                case "port": current?.port = Int(value) ?? 22
                case "proxyjump": current?.proxyJump = value
                default: break
                }
            }
        }
        if let current, !current.alias.contains("*") { result.append(current) }
        return result
    }

    static func export(_ hosts: [Host]) -> String {
        hosts.sorted { $0.label < $1.label }.map { host in
            """
            Host \(host.label.replacingOccurrences(of: " ", with: "-"))
              HostName \(host.address)
              User \(host.username)
              Port \(host.port)
            """
        }.joined(separator: "\n\n") + "\n"
    }
}
