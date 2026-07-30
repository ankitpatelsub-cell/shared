import Foundation

@MainActor
final class HostListViewModel: ObservableObject {
    @Published var searchText: String = ""

    func filteredGroups(from hosts: [Host]) -> [(title: String, hosts: [Host])] {
        let filtered = searchText.isEmpty
            ? hosts
            : hosts.filter { host in
                host.label.localizedCaseInsensitiveContains(searchText)
                    || host.address.localizedCaseInsensitiveContains(searchText)
                    || host.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }

        let grouped = Dictionary(grouping: filtered) { $0.groupName?.isEmpty == false ? $0.groupName! : "Ungrouped" }
        return grouped
            .map { (title: $0.key, hosts: $0.value.sorted { $0.label < $1.label }) }
            .sorted { $0.title < $1.title }
    }
}
