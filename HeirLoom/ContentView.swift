import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            LoomDebugView()
                .tabItem {
                    Label("Loomie Voice", systemImage: "waveform.circle.fill")
                }
                .tag(0)

            FamilyCloudView()
                .tabItem {
                    Label("Family & Atlas", systemImage: "person.3.sequence.fill")
                }
                .tag(1)
        }
    }
}

/// Interactive Family & MongoDB Atlas cloud explorer view
struct FamilyCloudView: View {
    @StateObject private var dbManager = MongoDBManager()
    @State private var showingAddSheet = false
    @State private var newName = ""
    @State private var newAgeText = "72"
    @State private var newInterestsText = "Ham Radio, Woodworking"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("MongoDB Atlas Connected")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.green)
                            Spacer()
                            Text(AppConfiguration.mongoDBDatabase)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text("Live sync enabled across HeirLoom corkboard nodes, oral history stories, and intergenerational sparks.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Family Members (\(dbManager.users.count))") {
                    if dbManager.users.isEmpty {
                        ContentUnavailableView("No Members Loaded", systemImage: "person.crop.circle.badge.questionmark", description: Text("Tap Fetch below to retrieve family tree from MongoDB Atlas."))
                    } else {
                        ForEach(dbManager.users) { user in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(user.name ?? user.title ?? "Family Member")
                                        .font(.headline)
                                    Spacer()
                                    if let gen = user.generationTier {
                                        Text("Gen \(gen)")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(genColor(gen).opacity(0.15))
                                            .foregroundStyle(genColor(gen))
                                            .clipShape(Capsule())
                                    }
                                }

                                if let desc = user.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                if let passions = user.interests, !passions.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 4) {
                                            ForEach(passions, id: \.self) { passion in
                                                Text(passion)
                                                    .font(.caption2)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.blue.opacity(0.1))
                                                    .foregroundStyle(.blue)
                                                    .clipShape(Capsule())
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                if let id = dbManager.users[index]._id {
                                    dbManager.deleteUser(id: id)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Family Corkboard")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button("Refresh Atlas") {
                            dbManager.fetchUsers()
                        }
                        Spacer()
                        Button("Add Test Member") {
                            dbManager.addUser(name: "Uncle Arthur", age: 74, interests: ["Printing Press", "Chicago History", "Vintage Bicycles"])
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                NavigationStack {
                    Form {
                        TextField("Full Name", text: $newName)
                        TextField("Age", text: $newAgeText)
                            .keyboardType(.numberPad)
                        TextField("Passions (comma-separated)", text: $newInterestsText)
                    }
                    .navigationTitle("New Family Member")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingAddSheet = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                let age = Int(newAgeText) ?? 70
                                let passions = newInterestsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                                dbManager.addUser(name: newName, age: age, interests: passions)
                                showingAddSheet = false
                                newName = ""
                            }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .onAppear {
                dbManager.fetchUsers()
            }
        }
    }

    private func genColor(_ gen: Int) -> Color {
        switch gen {
        case 1: return .purple
        case 2: return .orange
        case 3: return .teal
        default: return .blue
        }
    }
}

#Preview {
    ContentView()
}
