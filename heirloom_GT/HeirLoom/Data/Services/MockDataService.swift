import Foundation

/// Stable identifiers so previews, tests, and demo scripts can reference seeded entities.
enum MockIDs {
    static let joseph = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    static let eleanor = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    static let marcus = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    static let sarah = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
    static let alex = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!

    static let josephWorkshopMemory = UUID(uuidString: "00000000-0000-0000-0001-000000000001")!
    static let eleanorAirfieldMemory = UUID(uuidString: "00000000-0000-0000-0001-000000000002")!
    static let marcusMustangMemory = UUID(uuidString: "00000000-0000-0000-0001-000000000003")!
    static let alexSynthMemory = UUID(uuidString: "00000000-0000-0000-0001-000000000004")!
}

/// In-memory, fully offline implementation of every data-facing protocol, seeded with the Clarke family.
actor MockDataService: FamilyGraphRepositoryProtocol, LoomAgentServiceProtocol, StorybookServiceProtocol, TranscriptionServiceProtocol {
    static let radioStoryTranscript = """
        Back in the summer of '62 I ordered a Heathkit shortwave kit out of the back of Popular Electronics. \
        I built the whole thing on the kitchen table with a pencil-tip soldering iron, one tube socket at a time. \
        Your grandmother said the house smelled like rosin for a month. The first night it worked I made contact \
        with an operator in Nova Scotia, and I logged every call sign in a little green notebook I still keep in the workshop.
        """

    private let latency: Duration
    private var graph: FamilyGraph
    private var subscribers: [UUID: AsyncStream<FamilyGraph>.Continuation] = [:]

    init(latency: Duration = .milliseconds(600), graph: FamilyGraph = MockDataService.seededGraph()) {
        self.latency = latency
        self.graph = graph
    }

    // MARK: - Demo hooks

    /// Simulates Grandpa Joseph recording his ham radio story: adds the memory, bridges it to Alex's
    /// electronics hobbies, and raises a call-to-action spark on Alex's device.
    @discardableResult
    func simulateIngestionOfRadioStory() async -> MemoryIngestionResult {
        await simulateLatency()
        return applyRadioStory(transcript: Self.radioStoryTranscript, authorID: MockIDs.joseph)
    }

    func currentGraph() -> FamilyGraph {
        graph
    }

    // MARK: - FamilyGraphRepositoryProtocol

    func fetchGraph() async throws -> FamilyGraph {
        await simulateLatency()
        return graph
    }

    func add(_ memory: MemoryNode) async throws {
        graph.memories.append(memory)
        publish()
    }

    func pendingSparks(for memberID: UUID) async throws -> [LoomSpark] {
        graph.pendingSparks(for: memberID)
    }

    func resolveSpark(id: UUID) async throws {
        guard let index = graph.sparks.firstIndex(where: { $0.id == id }) else { return }
        graph.sparks[index].isResolved = true
        publish()
    }

    func graphUpdates() async -> AsyncStream<FamilyGraph> {
        let (stream, continuation) = AsyncStream.makeStream(of: FamilyGraph.self, bufferingPolicy: .bufferingNewest(1))
        let subscriberID = UUID()
        subscribers[subscriberID] = continuation
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removeSubscriber(subscriberID) }
        }
        continuation.yield(graph)
        return stream
    }

    // MARK: - TranscriptionServiceProtocol

    /// Mock mode only: every recording "contains" Joseph's radio story.
    func transcribe(audioAt url: URL) async throws -> String {
        await simulateLatency()
        return Self.radioStoryTranscript
    }

    // MARK: - LoomAgentServiceProtocol

    func ingestMemory(transcript: String, authorID: UUID) async throws -> MemoryIngestionResult {
        await simulateLatency()
        if transcript.localizedCaseInsensitiveContains("radio") {
            return applyRadioStory(transcript: transcript, authorID: authorID)
        }

        let memory = MemoryNode(
            authorID: authorID,
            rawTranscript: transcript,
            narrativeSummary: String(transcript.prefix(160)),
            extractedEra: "Unknown era",
            tags: ["unsorted"]
        )
        graph.memories.append(memory)
        publish()
        return MemoryIngestionResult(memory: memory)
    }

    func followUpQuestions(for memory: MemoryNode, sessionID: String) async throws -> [String] {
        await simulateLatency()
        if memory.hobbiesIdentified.contains("Ham Radio") {
            return [
                "Who was the most surprising person you ever reached on that radio?",
                "Do you still remember your call sign?",
                "What did you learn from that first build that you'd tell Alex about his guitar pedals?",
            ]
        }
        return [
            "Who else was there with you?",
            "What does that memory smell or sound like when you think about it now?",
            "What would you want your grandchildren to take away from this story?",
        ]
    }

    nonisolated func streamReply(to message: String, sessionID: String) -> AsyncThrowingStream<String, any Error> {
        let reply = "That's a wonderful detail. Tell me more about who taught you, and what it felt like the first time it worked."
        let tokenDelay = latency / 20
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for word in reply.split(separator: " ") {
                        try await Task.sleep(for: tokenDelay)
                        continuation.yield(String(word) + " ")
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - StorybookServiceProtocol

    func generateStorybook(memoryIDs: [UUID]) async throws -> [StoryChapter] {
        await simulateLatency()
        let selected = memoryIDs.isEmpty ? graph.memories : graph.memories.filter { memoryIDs.contains($0.id) }
        return selected
            .sorted { $0.timestamp < $1.timestamp }
            .map { memory in
                let author = graph.member(id: memory.authorID)?.name ?? "A Clarke"
                return StoryChapter(
                    title: "\(author), \(memory.extractedEra)",
                    narrativeText: memory.narrativeSummary,
                    illustrationURL: Self.placeholderIllustrationURL(seed: memory.id.uuidString),
                    sourceMemoryIDs: [memory.id]
                )
            }
    }

    func generateIllustration(prompt: String) async throws -> URL {
        await simulateLatency()
        return Self.placeholderIllustrationURL(seed: String(prompt.prefix(32)))
    }

    // MARK: - Private

    private func applyRadioStory(transcript: String, authorID: UUID) -> MemoryIngestionResult {
        // Repeated demo taps return the story already on the board instead of duplicating it.
        if let existing = graph.memories.first(where: { $0.authorID == authorID && $0.rawTranscript == transcript }) {
            return MemoryIngestionResult(
                memory: existing,
                newConnections: graph.hobbyConnections.filter { $0.sourceMemoryID == existing.id },
                sparks: graph.sparks.filter { $0.relatedMemoryID == existing.id }
            )
        }

        let memory = MemoryNode(
            authorID: authorID,
            rawTranscript: transcript,
            narrativeSummary: "In the summer of 1962, Joseph built a Heathkit shortwave radio by hand on the kitchen table, "
                + "soldering every joint himself, and made his first contact with an operator in Nova Scotia.",
            extractedEra: "1960s",
            location: "Clarke family kitchen, Dayton, Ohio",
            entitiesMentioned: ["Heathkit", "Popular Electronics", "Nova Scotia", "Eleanor Clarke"],
            hobbiesIdentified: ["Ham Radio", "Soldering", "Analog Electronics"],
            tags: ["ham radio", "electronics", "1962", "workshop"]
        )

        var connections: [HobbyConnection] = []
        var sparks: [LoomSpark] = []
        if graph.member(id: MockIDs.alex) != nil {
            connections.append(HobbyConnection(
                fromMemberID: authorID,
                toMemberID: MockIDs.alex,
                sharedInterest: "Analog electronics and soldering",
                matchRationale: "Joseph hand-soldered a tube radio kit in 1962; Alex builds guitar pedals and synthesizer "
                    + "circuits today. Both share through-hole soldering and signal-path debugging.",
                sourceMemoryID: memory.id
            ))
            sparks.append(LoomSpark(
                targetMemberID: MockIDs.alex,
                elderID: authorID,
                promptText: "Grandpa Joseph just shared how he built his first ham radio in 1962. "
                    + "Ask him about his soldering tips for your next pedal build.",
                actionType: .callPhone,
                relatedMemoryID: memory.id
            ))
        }

        graph.memories.append(memory)
        graph.hobbyConnections.append(contentsOf: connections)
        graph.sparks.append(contentsOf: sparks)
        publish()
        return MemoryIngestionResult(memory: memory, newConnections: connections, sparks: sparks)
    }

    private func publish() {
        for continuation in subscribers.values {
            continuation.yield(graph)
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }

    private func simulateLatency() async {
        guard latency > .zero else { return }
        try? await Task.sleep(for: latency)
    }

    private static func placeholderIllustrationURL(seed: String) -> URL? {
        let safeSeed = seed.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "heirloom"
        return URL(string: "https://picsum.photos/seed/\(safeSeed)/800/600")
    }
}

// MARK: - Seed data

extension MockDataService {
    static func seededGraph() -> FamilyGraph {
        FamilyGraph(
            members: seededMembers,
            memories: seededMemories,
            kinshipEdges: seededKinship,
            hobbyConnections: [
                HobbyConnection(
                    fromMemberID: MockIDs.joseph,
                    toMemberID: MockIDs.marcus,
                    sharedInterest: "Woodworking",
                    matchRationale: "Joseph taught Marcus joinery in the garage workshop; Marcus still builds furniture on weekends.",
                    sourceMemoryID: MockIDs.josephWorkshopMemory
                ),
            ],
            sparks: [
                LoomSpark(
                    targetMemberID: MockIDs.sarah,
                    elderID: MockIDs.eleanor,
                    promptText: "Eleanor's airfield story is now a storybook chapter. Take a look before Sunday dinner.",
                    actionType: .viewStory,
                    timestamp: date(2026, 9, 20),
                    relatedMemoryID: MockIDs.eleanorAirfieldMemory
                ),
            ]
        )
    }

    private static var seededMembers: [FamilyMember] {
        [
            FamilyMember(
                id: MockIDs.joseph,
                name: "Joseph Clarke",
                generationTier: .grandparents,
                relationshipLabel: "Grandfather",
                bio: "Retired aircraft mechanic and lifelong tinkerer. Licensed ham radio operator since 1963.",
                passionTags: ["Woodworking", "Ham Radio", "1960s Civil Aviation"],
                phoneNumber: "+15555550101"
            ),
            FamilyMember(
                id: MockIDs.eleanor,
                name: "Eleanor Clarke",
                generationTier: .grandparents,
                relationshipLabel: "Grandmother",
                bio: "Former airline operations clerk at Dayton Municipal Airport. Keeper of the family photo albums.",
                passionTags: ["1960s Civil Aviation", "Quilting", "Big Band Music"],
                phoneNumber: "+15555550102"
            ),
            FamilyMember(
                id: MockIDs.marcus,
                name: "Marcus Clarke",
                generationTier: .parents,
                relationshipLabel: "Father",
                bio: "High school physics teacher who restores classic cars with anyone who will hold a wrench.",
                passionTags: ["Woodworking", "Classic Cars", "Physics"],
                phoneNumber: "+15555550201"
            ),
            FamilyMember(
                id: MockIDs.sarah,
                name: "Sarah Clarke",
                generationTier: .parents,
                relationshipLabel: "Mother",
                bio: "Nurse and amateur genealogist; started the family's first digital archive.",
                passionTags: ["Genealogy", "Photography", "Baking"],
                phoneNumber: "+15555550202"
            ),
            FamilyMember(
                id: MockIDs.alex,
                name: "Alex Clarke",
                generationTier: .grandchildren,
                relationshipLabel: "Grandchild",
                bio: "Computer engineering student at Georgia Tech who builds modular synths and guitar pedals.",
                passionTags: ["Computer Engineering", "Synthesizer Music", "Guitar Pedals"],
                phoneNumber: "+15555550301"
            ),
        ]
    }

    private static var seededKinship: [KinshipEdge] {
        [
            KinshipEdge(fromID: MockIDs.joseph, toID: MockIDs.eleanor, relationType: .spouse),
            KinshipEdge(fromID: MockIDs.marcus, toID: MockIDs.sarah, relationType: .spouse),
            KinshipEdge(fromID: MockIDs.joseph, toID: MockIDs.marcus, relationType: .parent),
            KinshipEdge(fromID: MockIDs.eleanor, toID: MockIDs.marcus, relationType: .parent),
            KinshipEdge(fromID: MockIDs.marcus, toID: MockIDs.alex, relationType: .parent),
            KinshipEdge(fromID: MockIDs.sarah, toID: MockIDs.alex, relationType: .parent),
        ]
    }

    private static var seededMemories: [MemoryNode] {
        [
            MemoryNode(
                id: MockIDs.eleanorAirfieldMemory,
                authorID: MockIDs.eleanor,
                timestamp: date(2026, 8, 2),
                rawTranscript: "I worked the ticket counter when the first jets came through Dayton. We'd go up to the "
                    + "observation deck on breaks and listen to the tower chatter on Joseph's little receiver.",
                narrativeSummary: "Eleanor worked the Dayton airport counter as jet service arrived in the 1960s, "
                    + "spending breaks on the observation deck listening to tower radio.",
                extractedEra: "1960s",
                location: "Dayton Municipal Airport, Ohio",
                entitiesMentioned: ["Dayton Municipal Airport", "Joseph Clarke"],
                hobbiesIdentified: ["1960s Civil Aviation", "Ham Radio"],
                tags: ["aviation", "career", "1960s"]
            ),
            MemoryNode(
                id: MockIDs.josephWorkshopMemory,
                authorID: MockIDs.joseph,
                timestamp: date(2026, 8, 15),
                rawTranscript: "Every Saturday Marcus and I were in the garage. I made him cut dovetails by hand "
                    + "before I'd let him near the table saw.",
                narrativeSummary: "Joseph taught a young Marcus hand-cut dovetail joinery in the family garage "
                    + "every Saturday throughout the 1980s.",
                extractedEra: "1980s",
                location: "Clarke family garage, Dayton, Ohio",
                entitiesMentioned: ["Marcus Clarke"],
                hobbiesIdentified: ["Woodworking"],
                tags: ["workshop", "teaching", "father and son"]
            ),
            MemoryNode(
                id: MockIDs.marcusMustangMemory,
                authorID: MockIDs.marcus,
                timestamp: date(2026, 9, 1),
                rawTranscript: "Dad and I spent two summers rebuilding a '66 Mustang. He rewired the whole dash "
                    + "from memory.",
                narrativeSummary: "Marcus and Joseph rebuilt a 1966 Mustang over two summers in the 1990s, "
                    + "with Joseph rewiring the dashboard from memory.",
                extractedEra: "1990s",
                location: "Dayton, Ohio",
                entitiesMentioned: ["Joseph Clarke", "1966 Ford Mustang"],
                hobbiesIdentified: ["Classic Cars"],
                tags: ["cars", "restoration"]
            ),
            MemoryNode(
                id: MockIDs.alexSynthMemory,
                authorID: MockIDs.alex,
                timestamp: date(2026, 9, 18),
                rawTranscript: "Finished my first Eurorack oscillator module in the dorm. Took three tries to get "
                    + "the tuning stable.",
                narrativeSummary: "Alex completed a hand-built Eurorack oscillator module in his Georgia Tech dorm "
                    + "after three attempts to stabilize its tuning.",
                extractedEra: "2020s",
                location: "Georgia Tech, Atlanta",
                entitiesMentioned: ["Eurorack", "Georgia Tech"],
                hobbiesIdentified: ["Synthesizer Music", "Computer Engineering"],
                tags: ["synth", "electronics", "college"]
            ),
        ]
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        let components = DateComponents(calendar: Calendar(identifier: .gregorian), year: year, month: month, day: day)
        return components.date ?? .now
    }
}
