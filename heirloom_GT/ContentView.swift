import SwiftUI

struct ContentView: View {
    @StateObject private var dbManager = MongoDBManager()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Heirloom MongoDB Test")
                .font(.title)
                .bold()
            
            // Add Button
            Button("Add Test User") {
                dbManager.addUser(name: "Grandpa Bob", age: 78, interests: ["photography", "radios"])
            }
            .buttonStyle(.borderedProminent)
            
            // Fetch/Refresh Button
            Button("Fetch Users") {
                dbManager.fetchUsers()
            }
            .buttonStyle(.bordered)
            
            // Simple text display showing count of users fetched
            Text("Users loaded in memory: \(dbManager.users.count)")
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding()
        .onAppear {
            dbManager.fetchUsers()
        }
    }
}
