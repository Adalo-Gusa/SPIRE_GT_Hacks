import Foundation

/// Primary data layer service managing cloud persistence with MongoDB Atlas
/// for the HeirLoom family corkboard, stories, and intergenerational sparks.
///
/// Designed to satisfy the MLH "Best Use of MongoDB Atlas" prize:
/// 1. Persists to MongoDB Atlas through the HeirLoom FastAPI server (`heirloom-api/main.py`), which talks to
///    Atlas with a `MONGODB_URI` connection string. (The app used to call the Atlas Data API directly, but
///    MongoDB retired that API, so every write silently landed in the local cache instead.)
/// 2. Manages `members`, `stories`, and `sparks` collections.
/// 3. Keeps an in-memory 3-generation fallback cache so reads still work during live judging under flaky
///    venue Wi-Fi. Writes are cached locally too, but a failed write throws so callers can report it honestly.
actor MongoDBAtlasService {
    static let shared = MongoDBAtlasService()

    private let baseURL: URL
    private let urlSession: URLSession

    // MARK: - In-Memory Fallback Cache (Populated with Clarke Family 3-Gen Tree)

    private var localMembers: [String: MemberDocument] = [:]
    private var localStories: [StoryDocument] = []
    private var localSparks: [SparkDocument] = []
    private var localFeedPosts: [FeedPostDocument] = []

    init(baseURL: URL = AppConfiguration.heirloomAPIBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.urlSession = session
        initializeFallbackData()
    }

    // MARK: - Public API

    /// Fetches all members belonging to a family tree.
    func fetchFamilyMembers(familyId: String = AppConfiguration.mongoDBFamilyId) async throws -> [MemberDocument] {
        do {
            let data = try await send("GET", "members", query: ["family_id": familyId])
            let members = try Self.decoder.decode([MemberDocument].self, from: data)
            for member in members {
                localMembers[member._id] = member
            }
            return members
        } catch {
            print("[MongoDBAtlasService] fetchFamilyMembers failed: \(error.localizedDescription). Using local cache.")
            return Array(localMembers.values.filter { $0.familyId == familyId })
                .sorted { $0.generationTier < $1.generationTier }
        }
    }

    /// Fetches all ingested oral history stories for the family corkboard.
    func fetchStories(familyId: String = AppConfiguration.mongoDBFamilyId) async throws -> [StoryDocument] {
        do {
            let data = try await send("GET", "stories", query: ["family_id": familyId])
            let remote = try Self.decoder.decode([StoryDocument].self, from: data)

            // Keep stories that only exist locally (e.g. saved while offline) alongside the remote ones.
            var existingIds = Set(remote.map { $0._id })
            var combined = remote
            for local in localStories where !existingIds.contains(local._id) {
                combined.append(local)
                existingIds.insert(local._id)
            }
            localStories = combined
            return combined
        } catch {
            print("[MongoDBAtlasService] fetchStories failed: \(error.localizedDescription). Using local cache.")
            return localStories.filter { $0.familyId == familyId }
        }
    }

    /// Saves a new oral history story captured from Loomie to the Atlas `stories` collection.
    /// The story is cached locally first; throws if the server didn't store it.
    func insertStory(_ story: StoryDocument) async throws {
        if let idx = localStories.firstIndex(where: { $0._id == story._id }) {
            localStories[idx] = story
        } else {
            localStories.insert(story, at: 0)
        }

        _ = try await send("POST", "stories", body: Self.encoder.encode(story))
        print("[MongoDBAtlasService] Saved story '\(story.title)' to MongoDB Atlas collection 'stories'.")
    }

    /// Appends newly discovered hobbies / passions to a family member's profile in Atlas.
    /// Throws if the server didn't update it (including when the member doesn't exist in Atlas yet).
    func appendPassionsToMember(memberId: String, newPassions: [String]) async throws {
        guard !newPassions.isEmpty else { return }

        if var member = localMembers[memberId] {
            for passion in newPassions where !member.passions.contains(passion) {
                member.passions.append(passion)
            }
            member.updatedAt = Date()
            localMembers[memberId] = member
        }

        let body = try JSONSerialization.data(withJSONObject: ["passions": newPassions])
        _ = try await send("POST", "members/\(memberId)/passions", body: body)
        print("[MongoDBAtlasService] Added passions \(newPassions) to member '\(memberId)' in Atlas.")
    }

    /// Saves an intergenerational spark notification to the Atlas `sparks` collection.
    /// The spark is cached locally first; throws if the server didn't store it.
    func createSparkNotification(_ spark: SparkDocument) async throws {
        if let idx = localSparks.firstIndex(where: { $0._id == spark._id }) {
            localSparks[idx] = spark
        } else {
            localSparks.insert(spark, at: 0)
        }

        _ = try await send("POST", "sparks", body: Self.encoder.encode(spark))
        print("[MongoDBAtlasService] Saved spark '\(spark._id)' to MongoDB Atlas collection 'sparks'.")
    }

    /// Fetches all active spark connection alerts for the family.
    func fetchSparks(familyId: String = AppConfiguration.mongoDBFamilyId) async throws -> [SparkDocument] {
        do {
            let data = try await send("GET", "sparks", query: ["family_id": familyId])
            let remote = try Self.decoder.decode([SparkDocument].self, from: data)

            var existingIds = Set(remote.map { $0._id })
            var combined = remote
            for local in localSparks where !existingIds.contains(local._id) {
                combined.append(local)
                existingIds.insert(local._id)
            }
            localSparks = combined
            return combined
        } catch {
            print("[MongoDBAtlasService] fetchSparks failed: \(error.localizedDescription). Using local cache.")
            return localSparks.filter { $0.familyId == familyId }
        }
    }

    /// Fetches all social moments & Instagram updates for the Family Feed.
    func fetchFeedPosts(familyId: String = AppConfiguration.mongoDBFamilyId, authorId: String? = nil) async throws -> [FeedPostDocument] {
        var queryParams: [String: String] = ["family_id": familyId]
        if let authorId = authorId {
            queryParams["author_id"] = authorId
        }

        do {
            let data = try await send("GET", "posts", query: queryParams)
            let remote = try Self.decoder.decode([FeedPostDocument].self, from: data)

            var existingIds = Set(remote.map { $0._id })
            var combined = remote
            for local in localFeedPosts where !existingIds.contains(local._id) {
                combined.append(local)
                existingIds.insert(local._id)
            }
            localFeedPosts = combined
            return combined.sorted { $0.createdAt > $1.createdAt }
        } catch {
            print("[MongoDBAtlasService] fetchFeedPosts failed: \(error.localizedDescription). Using local cache.")
            return localFeedPosts
                .filter { $0.familyId == familyId && (authorId == nil || $0.authorId == authorId) }
                .sorted { $0.createdAt > $1.createdAt }
        }
    }

    /// Saves a newly shared post (from Instagram or in-app composer) to MongoDB Atlas.
    func insertFeedPost(_ post: FeedPostDocument) async throws {
        if let idx = localFeedPosts.firstIndex(where: { $0._id == post._id }) {
            localFeedPosts[idx] = post
        } else {
            localFeedPosts.insert(post, at: 0)
        }

        _ = try await send("POST", "posts", body: Self.encoder.encode(post))
        print("[MongoDBAtlasService] Saved feed post '\(post._id)' to MongoDB Atlas collection 'posts'.")
    }

    // MARK: - HTTP Transport

    /// The backend parses ISO 8601 dates (the default JSON date encoding would be misread).
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// Tolerates the backend's date formats (e.g. fractional seconds, with or without a time zone).
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let withZone = text.hasSuffix("Z") || text.range(of: #"[+-]\d\d:\d\d$"#, options: .regularExpression) != nil
                ? text : text + "Z"
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: withZone) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: withZone) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unreadable date \(text)"))
        }
        return decoder
    }()

    private func send(
        _ method: String,
        _ path: String,
        query: [String: String] = [:],
        body: Data? = nil
    ) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "HeirLoomAPI", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "HeirLoom API \(method) /\(path) returned HTTP \(http.statusCode): \(detail)"
            ])
        }
        return data
    }

    // MARK: - Live Judging Resilient Fallback Data (3 Generations of Clarke Family)

    private func initializeFallbackData() {
        let famId = AppConfiguration.mongoDBFamilyId

        // Generation 1 (Grandparents)
        let grandpaJoe = MemberDocument(
            id: "member_grandpa_joe",
            familyId: famId,
            name: "Joseph Clarke",
            birthYear: 1948,
            generationTier: 1,
            spouseId: "member_grandma_eleanor",
            parents: [],
            children: ["member_marcus"],
            passions: ["Ham Radio", "Woodworking", "Civil Aviation", "1960s Cars"],
            gender: "male",
            bio: "Retired civil aerospace engineer, lifelong ham radio enthusiast (K4JOC), and vintage car tinkerer."
        )

        let grandmaEleanor = MemberDocument(
            id: "member_grandma_eleanor",
            familyId: famId,
            name: "Eleanor Clarke",
            birthYear: 1950,
            generationTier: 1,
            spouseId: "member_grandpa_joe",
            parents: [],
            children: ["member_marcus"],
            passions: ["Baking", "Watercolor Painting", "Gardening"],
            gender: "female",
            bio: "Botanical watercolor artist and family holiday pastry anchor."
        )

        // Generation 2 (Parents)
        let marcus = MemberDocument(
            id: "member_marcus",
            familyId: famId,
            name: "Marcus Clarke",
            birthYear: 1976,
            generationTier: 2,
            spouseId: "member_sarah",
            parents: ["member_grandpa_joe", "member_grandma_eleanor"],
            children: ["member_alex"],
            passions: ["Cycling", "Photography", "Acoustic Guitar"],
            gender: "male",
            bio: "Landscape photographer, gravel cyclist, and acoustic folk guitarist."
        )

        let sarah = MemberDocument(
            id: "member_sarah",
            familyId: famId,
            name: "Sarah Clarke",
            birthYear: 1978,
            generationTier: 2,
            spouseId: "member_marcus",
            parents: [],
            children: ["member_alex"],
            passions: ["Pottery", "Trail Running"],
            gender: "female",
            bio: "Studio ceramic artist and ultrarunner exploring mountain passes."
        )

        // Generation 3 (Grandchild)
        let alex = MemberDocument(
            id: "member_alex",
            familyId: famId,
            name: "Alex Clarke",
            birthYear: 2004,
            generationTier: 3,
            spouseId: nil,
            parents: ["member_marcus", "member_sarah"],
            children: [],
            passions: ["Electronics", "Synthesizer Music", "Guitar Pedals", "Computer Engineering"],
            bio: "Georgia Tech CE sophomore building analog synthesizer filters, fuzz pedals, and audio DSP."
        )

        localMembers = [
            grandpaJoe._id: grandpaJoe,
            grandmaEleanor._id: grandmaEleanor,
            marcus._id: marcus,
            sarah._id: sarah,
            alex._id: alex
        ]

        // Seed Historical Story: Dorm Radio (1970)
        let radioStory = StoryDocument(
            id: "story_dorm_radio_1970",
            familyId: famId,
            authorId: "member_grandpa_joe",
            title: "Tinkering at 2 AM: The Dorm Radio",
            narrativeSummary: "In November 1970 in his college dorm room, Joe stayed up past 2 AM wiring a custom shortwave transmitter from salvaged aircraft parts. Through the crackling static, he picked up a ham radio operator in Oslo, Norway.",
            extractedEra: "1970",
            location: "Durham, NC",
            passions: ["Ham Radio", "Electronics"],
            peopleMentioned: ["Eleanor Clarke"],
            grokImaginePrompt: "A warm 1970s Kodachrome photograph of a 22-year-old student in a cozy college dorm room late at night, surrounded by glowing vacuum tubes, copper wiring, and an illuminated ham radio dial, soft warm amber glow, film grain",
            rawTranscript: "I remember it was November 1970 in our Duke dorm. Everyone was asleep, but I had this crate of salvaged aircraft relays and tube sockets spread across my desk. Around 2 AM, I tuned past the static and heard an operator in Oslo calling CQ.",
            imageUrl: "https://images.unsplash.com/photo-1550751827-4bd374c3f58b"
        )
        localStories = [radioStory]

        // Seed Intergenerational Spark
        let electronicsSpark = SparkDocument(
            id: "spark_electronics_joe_alex",
            familyId: famId,
            elderId: "member_grandpa_joe",
            targetMemberId: "member_alex",
            matchedPassion: "Electronics",
            sparkMessage: "Grandpa Joe built vacuum-tube shortwave transmitters in his college dorm in 1970—just like Alex is soldering guitar pedals and modular synth circuits today!",
            ctaAction: "Ask Grandpa Joe about the 2 AM Dorm Radio",
            isRead: false,
            status: "active"
        )
        localSparks = [electronicsSpark]

        // Seed Family Feed Posts (Instagram + In-App)
        let alexInstagramPost = FeedPostDocument(
            id: "post_alex_synth_001",
            familyId: famId,
            authorId: "member_alex",
            authorName: "Alex Clarke",
            authorAvatarUrl: "https://images.unsplash.com/photo-1539571696357-5a69c17a67c6",
            content: "Late night lab session at Georgia Tech! Soldered the final stage of this ladder filter module for the modular synth rack. Oscilloscope traces are looking super clean 🎛️⚡️",
            imageUrl: "https://images.unsplash.com/photo-1598488035139-bdbb2231ce04",
            postUrl: "https://instagram.com/p/DA_synth_lab",
            source: "instagram",
            passions: ["Electronics", "Synthesizer Music", "Guitar Pedals"],
            location: "Atlanta, GA",
            createdAt: Date().addingTimeInterval(-3600 * 4),
            isUnread: true
        )

        let sarahInAppPost = FeedPostDocument(
            id: "post_sarah_pottery_002",
            familyId: famId,
            authorId: "member_sarah",
            authorName: "Sarah Clarke",
            authorAvatarUrl: "https://images.unsplash.com/photo-1534528741775-53994a69daeb",
            content: "Unloading the kiln this morning! This batch of stoneware mugs and wood-fired vases turned out beautifully. Saving the warm earthy one for Sunday breakfast with Mom and Dad ☕️🏺",
            imageUrl: "https://images.unsplash.com/photo-1565193566173-7a0ee3dbe261",
            postUrl: nil,
            source: "in_app",
            passions: ["Pottery", "Crafts"],
            location: "Asheville, NC",
            createdAt: Date().addingTimeInterval(-3600 * 26),
            isUnread: false
        )

        localFeedPosts = [alexInstagramPost, sarahInAppPost]
    }
}

