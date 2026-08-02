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
        let (parsedHosts, _) = SSHConfigParser.parse(text)
        return parsedHosts.map { host in
            SSHConfigHost(
                alias: host.label,
                hostname: host.address,
                user: host.username,
                port: host.port,
                proxyJump: host.jumpHostLabel
            )
        }
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
