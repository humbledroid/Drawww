//
//  DrawwwApp.swift
//  Drawww
//
//  Created by Deathcode on 05/04/26.
//

import SwiftUI
import SwiftData

@main
struct DrawwwApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            FloorPlanProject.self,
            WallSegment.self,
            DimensionLine.self,
            TextLabel.self
        ])
    }
}
