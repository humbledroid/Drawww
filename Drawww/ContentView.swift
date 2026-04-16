//
//  ContentView.swift
//  Drawww
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Home screen — lists all projects, lets user create/open/delete/rename/export.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FloorPlanProject.modifiedAt, order: .reverse) private var projects: [FloorPlanProject]

    @State private var selectedProject: FloorPlanProject?
    @State private var renameTarget: FloorPlanProject?
    @State private var renameText: String = ""
    @State private var exportPDFDoc: ExportablePDF?
    @State private var showExport = false

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 20)]

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            newProjectCard
                            ForEach(projects) { project in
                                projectCard(project)
                            }
                        }
                        .padding(24)
                    }
                }
            }
            .navigationTitle("Floor Plan Studio")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        createProject()
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(item: $selectedProject) { project in
                FloorPlanEditorView(project: project)
            }
            .alert("Rename Project", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) { renameTarget = nil }
                Button("Save") {
                    if let target = renameTarget, !renameText.isEmpty {
                        target.name = renameText
                        target.touch()
                        try? modelContext.save()
                    }
                    renameTarget = nil
                }
            }
            .fileExporter(
                isPresented: $showExport,
                document: exportPDFDoc,
                contentType: .pdf,
                defaultFilename: "FloorPlan.pdf"
            ) { _ in
                exportPDFDoc = nil
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No projects yet")
                .font(.title2)
                .fontWeight(.medium)
            Text("Create your first floor plan to get started.")
                .foregroundColor(.secondary)
            Button {
                createProject()
            } label: {
                Label("Create Project", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundColor(.white)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Cards

    private var newProjectCard: some View {
        Button {
            createProject()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.accentColor)
                Text("New Project")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .foregroundColor(.secondary.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
    }

    private func projectCard(_ project: FloorPlanProject) -> some View {
        Button {
            selectedProject = project
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Thumbnail
                ProjectThumbnailView(project: project)
                    .frame(maxWidth: .infinity)
                    .frame(height: 130)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text("\(project.walls.count) walls • \(formattedDate(project.modifiedAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.top, 8)
                .padding(.horizontal, 4)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                renameText = project.name
                renameTarget = project
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                duplicate(project)
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            Button {
                exportPDF(project)
            } label: {
                Label("Export PDF", systemImage: "arrow.up.doc")
            }
            Divider()
            Button(role: .destructive) {
                delete(project)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func createProject() {
        let project = FloorPlanProject(name: "Untitled Plan")
        modelContext.insert(project)
        try? modelContext.save()
        selectedProject = project
    }

    private func delete(_ project: FloorPlanProject) {
        modelContext.delete(project)
        try? modelContext.save()
    }

    private func duplicate(_ project: FloorPlanProject) {
        let copy = FloorPlanProject(name: "\(project.name) Copy")
        copy.unitSystem = project.unitSystem
        copy.pointsPerRealUnit = project.pointsPerRealUnit
        modelContext.insert(copy)
        for wall in project.walls {
            let w = WallSegment(start: wall.start, end: wall.end, thickness: wall.thickness)
            w.project = copy
            copy.walls.append(w)
            modelContext.insert(w)
        }
        try? modelContext.save()
    }

    private func exportPDF(_ project: FloorPlanProject) {
        let data = PDFExporter.exportPDF(project: project)
        exportPDFDoc = ExportablePDF(data: data)
        DispatchQueue.main.async {
            showExport = true
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}

// MARK: - Project Thumbnail

/// Small preview of the project's walls, auto-fit to the card.
struct ProjectThumbnailView: View {
    let project: FloorPlanProject

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let walls = project.walls
                guard !walls.isEmpty else { return }

                var minX: CGFloat = .infinity
                var minY: CGFloat = .infinity
                var maxX: CGFloat = -.infinity
                var maxY: CGFloat = -.infinity
                for w in walls {
                    for p in [w.start, w.end] {
                        minX = min(minX, CGFloat(p.x)); minY = min(minY, CGFloat(p.y))
                        maxX = max(maxX, CGFloat(p.x)); maxY = max(maxY, CGFloat(p.y))
                    }
                }
                let bw: CGFloat = max(1, maxX - minX)
                let bh: CGFloat = max(1, maxY - minY)
                let pad: CGFloat = 16
                let scale: CGFloat = min((size.width - pad * 2) / bw, (size.height - pad * 2) / bh)
                let offsetX: CGFloat = (size.width - bw * scale) / 2 - minX * scale
                let offsetY: CGFloat = (size.height - bh * scale) / 2 - minY * scale

                for w in walls {
                    var path = Path()
                    path.move(to: CGPoint(x: CGFloat(w.start.x) * scale + offsetX, y: CGFloat(w.start.y) * scale + offsetY))
                    path.addLine(to: CGPoint(x: CGFloat(w.end.x) * scale + offsetX, y: CGFloat(w.end.y) * scale + offsetY))
                    ctx.stroke(path, with: .color(.primary), lineWidth: 1.5)
                }
            }
            .overlay(alignment: .center) {
                if project.walls.isEmpty {
                    Image(systemName: "square.dashed")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [FloorPlanProject.self, WallSegment.self, DimensionLine.self, TextLabel.self, DraftingShape.self, SectionCutLine.self, HeightMarker.self, StairSymbol.self, HatchRegion.self, ElevationArrow.self], inMemory: true)
}

