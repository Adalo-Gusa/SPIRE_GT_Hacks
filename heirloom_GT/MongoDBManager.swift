//
//  MongoDBManager.swift
//  heirloom_GT
//
//  Created by Adalo Gusa on 9/26/26.
//
import Foundation

struct UserProfile: Codable, Identifiable {
    var id: String? { _id }
    let _id: String?
    var name: String?
    var title: String?
    var description: String?
    var age: Int?
    var interests: [String]?
    var tags: [String]?
}

class MongoDBManager: ObservableObject {
    @Published var users: [UserProfile] = []
    
    // FastAPI server URL (localhost for iOS Simulator, or your computer's LAN IP / deployed URL for physical device)
    private let baseURL = "http://127.0.0.1:8000"
    
    // MARK: - GET (Read All)
    func fetchUsers() {
        guard let url = URL(string: "\(baseURL)/items") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let data = data {
                do {
                    let items = try JSONDecoder().decode([UserProfile].self, from: data)
                    DispatchQueue.main.async {
                        self.users = items
                    }
                } catch {
                    print("Error decoding items: \(error)")
                }
            }
        }.resume()
    }
    
    // MARK: - ADD (Create)
    func addUser(name: String, age: Int, interests: [String]) {
        guard let url = URL(string: "\(baseURL)/items") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "title": name,
            "description": "Age: \(age)",
            "tags": interests,
            "name": name,
            "age": age,
            "interests": interests
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        URLSession.shared.dataTask(with: request) { _, _, _ in
            self.fetchUsers() // Refresh list
        }.resume()
    }
    
    // MARK: - UPDATE
    func updateUserInterests(id: String, newInterests: [String]) {
        guard let url = URL(string: "\(baseURL)/items/\(id)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "tags": newInterests,
            "interests": newInterests
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        URLSession.shared.dataTask(with: request) { _, _, _ in
            self.fetchUsers() // Refresh list
        }.resume()
    }
    
    // MARK: - REMOVE (Delete)
    func deleteUser(id: String) {
        guard let url = URL(string: "\(baseURL)/items/\(id)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async {
                self.users.removeAll { $0._id == id }
            }
        }.resume()
    }
}
