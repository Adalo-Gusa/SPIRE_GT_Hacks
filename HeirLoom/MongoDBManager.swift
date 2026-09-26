//
//  MongoDBManager.swift
//  heirloom_GT
//
//  Created by Adalo Gusa on 9/26/26.
//  Upgraded with async/await, resilient fallback cache, and member model bridging.
//

import Foundation
import Combine

/// User profile representing a family member in HeirLoom, compatible with both
/// the FastAPI middleware and direct MongoDB Atlas documents.
public struct UserProfile: Codable, Identifiable, Equatable {
    public var id: String { _id ?? UUID().uuidString }
    public var _id: String?
    public var name: String?
    public var title: String?
    public var description: String?
    public var age: Int?
    public var interests: [String]?
    public var tags: [String]?
    public var generationTier: Int?
    public var bio: String?

    enum CodingKeys: String, CodingKey {
        case _id
        case id
        case name
        case title
        case description
        case age
        case interests
        case tags
        case passions
        case generationTier = "generation_tier"
        case bio
    }

    public init(
        id: String? = nil,
        name: String? = nil,
        title: String? = nil,
        description: String? = nil,
        age: Int? = nil,
        interests: [String]? = nil,
        tags: [String]? = nil,
        generationTier: Int? = 1,
        bio: String? = nil
    ) {
        self._id = id
        self.name = name
        self.title = title ?? name
        self.description = description
        self.age = age
        self.interests = interests ?? tags
        self.tags = tags ?? interests
        self.generationTier = generationTier
        self.bio = bio
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self._id = (try? container.decode(String.self, forKey: ._id))
            ?? (try? container.decode(String.self, forKey: .id))
        self.name = try? container.decode(String.self, forKey: .name)
        self.title = try? container.decode(String.self, forKey: .title)
        self.description = try? container.decode(String.self, forKey: .description)
        self.age = try? container.decode(Int.self, forKey: .age)
        
        let ints = try? container.decode([String].self, forKey: .interests)
        let pass = try? container.decode([String].self, forKey: .passions)
        let tgs = try? container.decode([String].self, forKey: .tags)
        self.interests = ints ?? pass ?? tgs ?? []
        self.tags = tgs ?? self.interests
        self.generationTier = try? container.decode(Int.self, forKey: .generationTier)
        self.bio = try? container.decode(String.self, forKey: .bio)
        
        if self.name == nil && self.title != nil {
            self.name = self.title
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(_id, forKey: ._id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(age, forKey: .age)
        try container.encodeIfPresent(interests, forKey: .interests)
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encodeIfPresent(generationTier, forKey: .generationTier)
        try container.encodeIfPresent(bio, forKey: .bio)
    }

    /// Converts to corkboard tree MemberDocument
    public func toMemberDocument(familyId: String = "fam_clarke_001") -> MemberDocument {
        let birthYear = age.map { Calendar.current.component(.year, from: Date()) - $0 } ?? 1970
        return MemberDocument(
            id: _id ?? UUID().uuidString,
            familyId: familyId,
            name: name ?? title ?? "Family Member",
            birthYear: birthYear,
            generationTier: generationTier ?? 1,
            passions: interests ?? tags ?? [],
            bio: bio ?? description
        )
    }
}

/// Observable state manager for HeirLoom MongoDB backend integration.
@MainActor
public final class MongoDBManager: ObservableObject {
    @Published public var users: [UserProfile] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil

    /// Server URL (FastAPI middleware host).
    /// Default to localhost:8000, configurable via AppConfiguration.
    public var baseURL: String

    public init(baseURL: String = "http://127.0.0.1:8000") {
        self.baseURL = baseURL
        loadFallbackUsers()
    }

    // MARK: - Modern Async / Await API

    /// Fetches all users/members from MongoDB middleware with offline fallback.
    public func fetchUsersAsync() async {
        isLoading = true
        errorMessage = nil

        // Try /members first, then /items
        let endpoints = ["\(baseURL)/members", "\(baseURL)/items"]
        var loadedUsers: [UserProfile]? = nil

        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 4

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    let items = try JSONDecoder().decode([UserProfile].self, from: data)
                    loadedUsers = items
                    break
                }
            } catch {
                // Continue to next endpoint or fallback
            }
        }

        isLoading = false

        if let loaded = loadedUsers, !loaded.isEmpty {
            self.users = loaded
            print("[MongoDBManager] Successfully fetched \(loaded.count) users from MongoDB API.")
        } else {
            print("[MongoDBManager] Backend not reachable, displaying \(users.count) local family profiles.")
        }
    }

    /// Creates and persists a new family member/user in MongoDB.
    @discardableResult
    public func addUserAsync(name: String, age: Int, interests: [String]) async -> Bool {
        isLoading = true
        errorMessage = nil

        let newUser = UserProfile(
            id: "usr_\(UUID().uuidString.prefix(8))",
            name: name,
            title: name,
            description: "Age: \(age)",
            age: age,
            interests: interests,
            tags: interests
        )

        // Optimistic update
        users.append(newUser)

        let payload: [String: Any] = [
            "_id": newUser.id,
            "name": name,
            "title": name,
            "age": age,
            "birth_year": Calendar.current.component(.year, from: Date()) - age,
            "description": "Age: \(age)",
            "interests": interests,
            "tags": interests,
            "passions": interests,
            "generation_tier": age > 65 ? 1 : (age > 35 ? 2 : 3),
            "family_id": "fam_clarke_001"
        ]

        let endpoints = ["\(baseURL)/members", "\(baseURL)/items"]
        var success = false

        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 4
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    success = true
                    break
                }
            } catch {
                // Keep local optimistic user
            }
        }

        isLoading = false
        return success
    }

    /// Updates interests/passions for an existing user.
    @discardableResult
    public func updateUserInterestsAsync(id: String, newInterests: [String]) async -> Bool {
        // Optimistic local update
        if let idx = users.firstIndex(where: { $0.id == id || $0._id == id }) {
            var updated = users[idx]
            updated.interests = newInterests
            updated.tags = newInterests
            users[idx] = updated
        }

        let payload: [String: Any] = [
            "interests": newInterests,
            "tags": newInterests,
            "passions": newInterests
        ]

        let endpoints = ["\(baseURL)/members/\(id)", "\(baseURL)/items/\(id)"]
        var success = false

        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 4
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    success = true
                    break
                }
            } catch {
                // Kept local update
            }
        }

        return success
    }

    /// Deletes a user by ID.
    @discardableResult
    public func deleteUserAsync(id: String) async -> Bool {
        users.removeAll { $0.id == id || $0._id == id }

        let endpoints = ["\(baseURL)/members/\(id)", "\(baseURL)/items/\(id)"]
        var success = false

        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.timeoutInterval = 4

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    success = true
                    break
                }
            } catch {
                // Kept local deletion
            }
        }

        return success
    }

    // MARK: - Backward-Compatible Synchronous / Closure Signatures
    // Preserves 100% compatibility with Adalo Gusa's existing SwiftUI buttons

    public func fetchUsers() {
        Task {
            await fetchUsersAsync()
        }
    }

    public func addUser(name: String, age: Int, interests: [String]) {
        Task {
            await addUserAsync(name: name, age: age, interests: interests)
        }
    }

    public func updateUserInterests(id: String, newInterests: [String]) {
        Task {
            await updateUserInterestsAsync(id: id, newInterests: newInterests)
        }
    }

    public func deleteUser(id: String) {
        Task {
            await deleteUserAsync(id: id)
        }
    }

    // MARK: - Resilient Local Fallback

    private func loadFallbackUsers() {
        if users.isEmpty {
            users = [
                UserProfile(
                    id: "member_grandpa_joe",
                    name: "Joseph Clarke",
                    title: "Grandpa Joe",
                    description: "Age: 78",
                    age: 78,
                    interests: ["Ham Radio", "Woodworking", "Civil Aviation", "1960s Cars"],
                    tags: ["Ham Radio", "Woodworking", "Civil Aviation"],
                    generationTier: 1,
                    bio: "Retired aerospace engineer and lifelong ham radio tinkerer."
                ),
                UserProfile(
                    id: "member_grandma_eleanor",
                    name: "Eleanor Clarke",
                    title: "Grandma Eleanor",
                    description: "Age: 76",
                    age: 76,
                    interests: ["Baking", "Watercolor Painting", "Gardening"],
                    tags: ["Baking", "Watercolor Painting", "Gardening"],
                    generationTier: 1,
                    bio: "Botanical artist and family holiday pastry anchor."
                ),
                UserProfile(
                    id: "member_marcus",
                    name: "Marcus Clarke",
                    title: "Marcus Clarke",
                    description: "Age: 50",
                    age: 50,
                    interests: ["Cycling", "Photography", "Acoustic Guitar"],
                    tags: ["Cycling", "Photography", "Acoustic Guitar"],
                    generationTier: 2,
                    bio: "Landscape photographer and gravel cyclist."
                ),
                UserProfile(
                    id: "member_sarah",
                    name: "Sarah Clarke",
                    title: "Sarah Clarke",
                    description: "Age: 48",
                    age: 48,
                    interests: ["Pottery", "Trail Running"],
                    tags: ["Pottery", "Trail Running"],
                    generationTier: 2,
                    bio: "Studio ceramic artist and ultrarunner."
                ),
                UserProfile(
                    id: "member_alex",
                    name: "Alex Clarke",
                    title: "Alex Clarke",
                    description: "Age: 22",
                    age: 22,
                    interests: ["Electronics", "Synthesizer Music", "Guitar Pedals", "Computer Engineering"],
                    tags: ["Electronics", "Synthesizer Music", "Guitar Pedals"],
                    generationTier: 3,
                    bio: "Georgia Tech CE sophomore building analog synthesizer pedals."
                )
            ]
        }
    }
}
