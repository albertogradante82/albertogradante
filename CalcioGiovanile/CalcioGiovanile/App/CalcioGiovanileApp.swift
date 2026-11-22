import SwiftUI
import SwiftData

@main
struct CalcioGiovanileApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Team.self, Player.self, Match.self, Track.self, MatchEvent.self])
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            MatchListView()
                .tabItem { Label("Partite", systemImage: "sportscourt") }
            TeamListView()
                .tabItem { Label("Squadre", systemImage: "person.3") }
        }
    }
}
