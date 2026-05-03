//
//  TP7RemoteApp.swift
//  TP7Remote
//
//  Created by Jocelyn Manger on 5/3/26.
//

import SwiftUI
import CoreData

@main
struct TP7RemoteApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
