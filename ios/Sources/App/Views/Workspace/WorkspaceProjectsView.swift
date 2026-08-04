import SwiftUI
import SwiftData

struct WorkspaceProjectsView: View {
    @Query(sort: \WorkspaceProject.name) private var projects: [WorkspaceProject]
    @Environment(\.modelContext) private var modelContext
    @State private var showingNewProject = false
    @State private var selectedProject: WorkspaceProject?

    var body: some View {
        NavigationStack {
            if projects.isEmpty {
                ContentUnavailableView(
                    "No Projects",
                    systemImage: "folder.badge.plus",
                    description: Text("Create projects to organize your workspaces")
                )
                .navigationTitle("Workspace Projects")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingNewProject = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            } else {
                List(projects) { project in
                    NavigationLink(destination: ProjectDetailView(project: project)) {
                        HStack(spacing: 12) {
                            Image(systemName: project.icon)
                                .foregroundStyle(project.displayColor)
                                .font(.headline)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(project.name)
                                    .fontWeight(.semibold)

                                if let description = project.details {
                                    Text(description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Text("\(project.workspaceIDs.count) workspace\(project.workspaceIDs.count == 1 ? "" : "s")")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            modelContext.delete(project)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .navigationTitle("Workspace Projects")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingNewProject = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewProject) {
            NewProjectView(isPresented: $showingNewProject)
        }
    }
}

struct ProjectDetailView: View {
    @Bindable var project: WorkspaceProject
    @Environment(\.modelContext) private var modelContext
    @State private var isEditing = false

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Menu {
                        ForEach(WorkspaceProject.icons, id: \.self) { icon in
                            Button {
                                project.icon = icon
                            } label: {
                                HStack {
                                    Image(systemName: icon)
                                    Text(icon)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: project.icon)
                            .foregroundStyle(project.displayColor)
                            .font(.system(size: 32, weight: .semibold))
                            .frame(width: 50, height: 50)
                            .background(project.displayColor.opacity(0.1))
                            .cornerRadius(12)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Project Name", text: $project.name)
                            .font(.headline)
                            .disabled(!isEditing)

                        if isEditing {
                            Menu {
                                ForEach(WorkspaceProject.colors, id: \.self) { color in
                                    Button {
                                        project.color = color
                                    } label: {
                                        HStack {
                                            Circle()
                                                .fill(WorkspaceProject(name: "", color: color).displayColor)
                                            Text(color.capitalized)
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(project.displayColor)
                                        .frame(width: 12, height: 12)
                                    Text(project.color.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Spacer()

                    Button {
                        isEditing.toggle()
                    } label: {
                        Image(systemName: isEditing ? "checkmark" : "pencil")
                            .foregroundStyle(.blue)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                if isEditing {
                    TextField("Description", text: Binding(
                        get: { project.details ?? "" },
                        set: { project.details = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .frame(height: 80)
                }
            }
            .padding()

            if !project.workspaceIDs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Workspaces (\(project.workspaceIDs.count))")
                        .font(.headline)
                        .padding(.horizontal)

                    List {
                        ForEach(project.workspaceIDs, id: \.self) { id in
                            HStack {
                                Text("Workspace")
                                Spacer()
                                Button(role: .destructive) {
                                    project.workspaceIDs.removeAll { $0 == id }
                                } label: {
                                    Image(systemName: "xmark.circle")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }

            Spacer()
        }
        .navigationTitle("Edit Project")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NewProjectView: View {
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var description = ""
    @State private var selectedIcon = "folder"
    @State private var selectedColor = "blue"

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Info") {
                    TextField("Project Name", text: $name)
                    TextField("Description", text: $description, axis: .vertical)
                        .frame(height: 80)
                }

                Section("Appearance") {
                    Picker("Icon", selection: $selectedIcon) {
                        ForEach(WorkspaceProject.icons, id: \.self) { icon in
                            HStack {
                                Image(systemName: icon)
                                Text(icon.capitalized)
                            }
                            .tag(icon)
                        }
                    }

                    Picker("Color", selection: $selectedColor) {
                        ForEach(WorkspaceProject.colors, id: \.self) { color in
                            HStack {
                                Circle()
                                    .fill(WorkspaceProject(name: "", color: color).displayColor)
                                Text(color.capitalized)
                            }
                            .tag(color)
                        }
                    }
                }

                Section("Preview") {
                    HStack(spacing: 12) {
                        Image(systemName: selectedIcon)
                            .foregroundStyle(WorkspaceProject(name: "", color: selectedColor).displayColor)
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(name.isEmpty ? "Project Name" : name)
                                .fontWeight(.semibold)
                            Text(description.isEmpty ? "Description" : description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        let project = WorkspaceProject(
                            name: name,
                            description: description.isEmpty ? nil : description,
                            icon: selectedIcon,
                            color: selectedColor
                        )
                        modelContext.insert(project)
                        isPresented = false
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

#Preview {
    WorkspaceProjectsView()
}
