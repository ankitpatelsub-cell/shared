import Foundation

/// Parses OpenSSH `~/.ssh/config` files into TermVault `Host` and `Identity` models.
/// Supports a practical subset of `ssh_config(5)` directives.
struct SSHConfigParser {
    
    struct ParsedHost: Identifiable {
        let id = UUID()
        let label: String
        let address: String
        let port: Int
        let username: String
        let authMethod: HostAuthMethod
        let identityLabel: String?
        let jumpHostLabel: String?
        let startupSnippet: String?
        let groupName: String?
        let tags: [String]
        let themeName: String?
        
        // Raw config for advanced options
        let rawConfig: [String: String]
    }
    
    struct ParsedIdentity: Identifiable {
        let id = UUID()
        let label: String
        let keyType: IdentityKeyType
        let privateKeyPath: String
        let passphrase: String?
    }
    
    /// Parse SSH config from string content
    static func parse(_ content: String) -> (hosts: [ParsedHost], identities: [ParsedIdentity]) {
        var hosts: [ParsedHost] = []
        var identities: [ParsedIdentity] = []
        var currentHost: HostBuilder?
        var currentIdentity: IdentityBuilder?
        
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip comments and empty lines
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            
            let components = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
            guard let keyword = components.first?.lowercased() else { continue }
            let value = components.count > 1 ? components[1] : ""
            
            switch keyword {
            case "host":
                // Save previous host
                if let builder = currentHost {
                    hosts.append(builder.build())
                }
                // Host can have multiple patterns (Host host1 host2)
                let patterns = value.split(separator: " ").map(String.init)
                currentHost = HostBuilder(patterns: patterns)
                
            case "hostname":
                currentHost?.hostname = value
                
            case "port":
                currentHost?.port = Int(value) ?? 22
                
            case "user":
                currentHost?.username = value
                
            case "identityfile":
                currentHost?.identityFile = expandTilde(value)
                // Also create identity entry
                let identityLabel = URL(fileURLWithPath: expandTilde(value)).deletingPathExtension().lastPathComponent
                if !identities.contains(where: { $0.label == identityLabel }) {
                    currentIdentity = IdentityBuilder(label: identityLabel, privateKeyPath: expandTilde(value))
                    identities.append(currentIdentity!.build())
                }
                
            case "pubkeyauthentication":
                currentHost?.pubkeyAuth = (value.lowercased() == "yes")
                
            case "passwordauthentication":
                currentHost?.passwordAuth = (value.lowercased() == "yes")
                
            case "proxyjump", "proxycommand":
                if keyword == "proxyjump" {
                    currentHost?.jumpHostLabel = value
                } else if value.hasPrefix("ssh ") && value.contains("-W") {
                    // Parse ProxyCommand for jump host
                    let parts = value.split(separator: " ")
                    if let idx = parts.firstIndex(of: "-W"), idx + 1 < parts.count {
                        currentHost?.jumpHostLabel = String(parts[idx + 1]).replacingOccurrences(of: "%h:%p", with: "")
                    }
                }
                
            case "sendenv":
                // Store for potential startup snippet
                currentHost?.sendEnv.append(value)
                
            case "localtunnel", "remotetunnel", "dynamicforward":
                // Port forwarding - could be stored for UI
                currentHost?.portForwards.append("\(keyword) \(value)")
                
            case "serveraliveinterval":
                currentHost?.serverAliveInterval = Int(value)
                
            case "serveralivecountmax":
                currentHost?.serverAliveCountMax = Int(value)
                
            case "tcpkeepalive":
                currentHost?.tcpKeepAlive = (value.lowercased() == "yes")
                
            case "stricthostkeychecking":
                currentHost?.strictHostKeyChecking = value.lowercased()
                
            case "userknownhostsfile":
                currentHost?.userKnownHostsFile = expandTilde(value)
                
            case "controlmaster":
                currentHost?.controlMaster = value
                
            case "controlpath":
                currentHost?.controlPath = expandTilde(value)
                
            case "controlpersist":
                currentHost?.controlPersist = value
                
            case "forwardagent":
                currentHost?.forwardAgent = (value.lowercased() == "yes")
                
            case "forwardx11":
                currentHost?.forwardX11 = (value.lowercased() == "yes")
                
            case "compression":
                currentHost?.compression = (value.lowercased() == "yes")
            
            // Identity-specific directives (inside Match or separate IdentityFile blocks)
            case "identityfile" where currentIdentity != nil:
                currentIdentity?.privateKeyPath = expandTilde(value)
                
            default:
                // Store unknown directives in raw config
                currentHost?.rawConfig[keyword] = value
            }
        }
        
        // Don't forget the last host
        if let builder = currentHost {
            hosts.append(builder.build())
        }
        
        return (hosts, identities)
    }
    
    /// Parse SSH config from file URL
    static func parseFile(at url: URL) throws -> (hosts: [ParsedHost], identities: [ParsedIdentity]) {
        let content = try String(contentsOf: url, encoding: .utf8)
        return parse(content)
    }
    
    /// Parse SSH config from default location (~/.ssh/config)
    static func parseDefault() throws -> (hosts: [ParsedHost], identities: [ParsedIdentity]) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configURL = home.appendingPathComponent(".ssh/config")
        return try parseFile(at: configURL)
    }
    
    private static func expandTilde(_ path: String) -> String {
        if path.hasPrefix("~/") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return home + path.dropFirst()
        }
        return path
    }
}

// MARK: - Builders

private class HostBuilder {
    var patterns: [String]
    var hostname: String = ""
    var port: Int = 22
    var username: String = ""
    var identityFile: String?
    var pubkeyAuth: Bool = true
    var passwordAuth: Bool = true
    var jumpHostLabel: String?
    var sendEnv: [String] = []
    var portForwards: [String] = []
    var serverAliveInterval: Int?
    var serverAliveCountMax: Int?
    var tcpKeepAlive: Bool = true
    var strictHostKeyChecking: String = "ask"
    var userKnownHostsFile: String?
    var controlMaster: String?
    var controlPath: String?
    var controlPersist: String?
    var forwardAgent: Bool = false
    var forwardX11: Bool = false
    var compression: Bool = false
    var rawConfig: [String: String] = [:]
    
    init(patterns: [String]) {
        self.patterns = patterns
    }
    
    func build() -> SSHConfigParser.ParsedHost {
        // Use first non-wildcard pattern as label, or first pattern
        let label = patterns.first { !$0.contains("*") && !$0.contains("?") } ?? patterns.first ?? "imported"
        
        // Determine auth method
        let authMethod: HostAuthMethod
        if let identityFile, !identityFile.isEmpty {
            authMethod = .privateKey
        } else if passwordAuth {
            authMethod = .password
        } else {
            authMethod = .none
        }
        
        // Build raw config string for advanced options
        var configStrings: [String] = []
        if let serverAliveInterval { configStrings.append("ServerAliveInterval \(serverAliveInterval)") }
        if let serverAliveCountMax { configStrings.append("ServerAliveCountMax \(serverAliveCountMax)") }
        if !tcpKeepAlive { configStrings.append("TCPKeepAlive no") }
        if strictHostKeyChecking != "ask" { configStrings.append("StrictHostKeyChecking \(strictHostKeyChecking)") }
        if let userKnownHostsFile { configStrings.append("UserKnownHostsFile \(userKnownHostsFile)") }
        if let controlMaster { configStrings.append("ControlMaster \(controlMaster)") }
        if let controlPath { configStrings.append("ControlPath \(controlPath)") }
        if let controlPersist { configStrings.append("ControlPersist \(controlPersist)") }
        if forwardAgent { configStrings.append("ForwardAgent yes") }
        if forwardX11 { configStrings.append("ForwardX11 yes") }
        if compression { configStrings.append("Compression yes") }
        configStrings.append(contentsOf: portForwards)
        configStrings.append(contentsOf: sendEnv.map { "SendEnv \($0)" })
        rawConfig.forEach { configStrings.append("\($0.key) \($0.value)") }
        
        return SSHConfigParser.ParsedHost(
            label: label,
            address: hostname.isEmpty ? label : hostname,
            port: port,
            username: username.isEmpty ? "root" : username,
            authMethod: authMethod,
            identityLabel: identityFile.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent },
            jumpHostLabel: jumpHostLabel,
            startupSnippet: configStrings.isEmpty ? nil : configStrings.joined(separator: "\n"),
            groupName: "Imported",
            tags: ["ssh-config"],
            themeName: nil,
            rawConfig: rawConfig
        )
    }
}

private class IdentityBuilder {
    var label: String
    var privateKeyPath: String
    var passphrase: String?
    
    init(label: String, privateKeyPath: String) {
        self.label = label
        self.privateKeyPath = privateKeyPath
    }
    
    func build() -> SSHConfigParser.ParsedIdentity {
        // Try to detect key type from file
        let keyType: IdentityKeyType
        if privateKeyPath.hasSuffix(".pub") {
            // Can't determine from .pub alone, default to ed25519
            keyType = .ed25519
        } else {
            keyType = .ed25519 // Default, will be detected on import
        }
        
        return SSHConfigParser.ParsedIdentity(
            label: label,
            keyType: keyType,
            privateKeyPath: privateKeyPath,
            passphrase: passphrase
        )
    }
}