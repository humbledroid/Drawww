//
//  ContentView.swift
//  Drawww
//
//  Created by Deathcode on 05/04/26.
//

import SwiftUI
import SwiftData

/// Root view: launches straight into the canvas (no onboarding wall).
/// Creates a default project if none exists.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FloorPlanProject.modifiedAt, order: .reverse) private var projects: [FloorPlanProject]

    var body: some View {
        Group {
            if let project = projects.first {
                FloorPlanEditorView(project: project)
            } else {
                // Will auto-create on appear
                ProgressView("Setting up...")
                    .onAppear { createDefaultProject() }
            }
        }
    }

    private func createDefaultProject() {
        let project = FloorPlanProject(name: "My Floor Plan")
        modelContext.insert(project)
        try? modelContext.save()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [FloorPlanProject.self, WallSegment.self, DimensionLine.self, TextLabel.self, DraftingShape.self, SectionCutLine.self, HeightMarker.self, StairSymbol.self, HatchRegion.self, ElevationArrow.self], inMemory: true)
}
