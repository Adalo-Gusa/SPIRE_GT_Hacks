import Foundation
import Testing
@testable import heirloom_GT

struct AudioLevelTests {
    @Test(arguments: [
        (Float(0), Float(1)),
        (Float(-30), Float(0.5)),
        (Float(-60), Float(0)),
        (Float(-120), Float(0)),
        (Float(6), Float(1)),
        (-Float.infinity, Float(0)),
        (Float.nan, Float(0)),
    ])
    func normalizedLevel(decibels: Float, expected: Float) {
        #expect(abs(AudioRecorderService.normalizedLevel(fromDecibels: decibels) - expected) < 0.0001)
    }
}

struct WireFormatTests {
    /// Shape produced by `middleware/models.py` (`FamilyGraph.model_dump_json()`).
    static let middlewareGraph = Data("""
    {
      "members": [{
        "id": "00000000-0000-0000-0000-000000000101",
        "name": "Joseph Clarke",
        "generation_tier": 1,
        "relationship_label": "Grandfather",
        "bio": "Tinkerer",
        "profile_image_url": null,
        "passion_tags": ["Ham Radio"],
        "phone_number": "+15555550101"
      }],
      "memories": [{
        "id": "00000000-0000-0000-0001-000000000001",
        "author_id": "00000000-0000-0000-0000-000000000101",
        "timestamp": "2026-09-26T07:05:03.123Z",
        "raw_transcript": "t",
        "narrative_summary": "s",
        "extracted_era": "1960s",
        "location": null,
        "entities_mentioned": [],
        "hobbies_identified": ["Ham Radio"],
        "tags": [],
        "media_urls": []
      }],
      "kinship_edges": [{
        "from_id": "00000000-0000-0000-0000-000000000101",
        "to_id": "00000000-0000-0000-0000-000000000301",
        "relation_type": "parent"
      }],
      "hobby_connections": [],
      "sparks": [{
        "id": "00000000-0000-0000-0002-000000000001",
        "target_member_id": "00000000-0000-0000-0000-000000000301",
        "elder_id": "00000000-0000-0000-0000-000000000101",
        "prompt_text": "Call Joseph",
        "action_type": "call_phone",
        "timestamp": "2026-09-26T07:05:03Z",
        "related_memory_id": null,
        "is_resolved": false
      }]
    }
    """.utf8)

    @Test func decodesMiddlewareGraph() throws {
        let graph = try JSONDecoder.heirLoom().decode(FamilyGraph.self, from: Self.middlewareGraph)
        #expect(graph.members.first?.id == MockIDs.joseph)
        #expect(graph.members.first?.generationTier == .grandparents)
        #expect(graph.members.first?.profileImageURL == nil)
        #expect(graph.memories.first?.location == nil)
        #expect(graph.kinshipEdges.first?.relationType == .parent)
        #expect(graph.sparks.first?.actionType == .callPhone)

        let millis = try #require(graph.memories.first?.timestamp)
        #expect(abs(millis.timeIntervalSince1970.truncatingRemainder(dividingBy: 1) - 0.123) < 0.001)
    }

    @Test func graphRoundTrips() throws {
        let original = MockDataService.seededGraph()
        let data = try JSONEncoder.heirLoom().encode(original)
        let decoded = try JSONDecoder.heirLoom().decode(FamilyGraph.self, from: data)
        #expect(decoded.members == original.members)
        #expect(decoded.memories.map(\.id) == original.memories.map(\.id))
        #expect(decoded.sparks.map(\.id) == original.sparks.map(\.id))
    }

    @Test func rejectsNonISODates() {
        let bad = Data(#"{"id":"00000000-0000-0000-0002-000000000001","target_member_id":"00000000-0000-0000-0000-000000000301","elder_id":"00000000-0000-0000-0000-000000000101","prompt_text":"p","action_type":"call_phone","timestamp":"yesterday","is_resolved":false}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder.heirLoom().decode(LoomSpark.self, from: bad)
        }
    }

    @Test func httpErrorsShowOnlyServerDetail() {
        let detail = NetworkError.httpStatus(502, Data(#"{"detail":"Grok timed out"}"#.utf8))
        #expect(detail.errorDescription == "Server returned HTTP 502: Grok timed out")

        let raw = NetworkError.httpStatus(500, Data("<html>stack trace with secrets</html>".utf8))
        #expect(raw.errorDescription == "Server returned HTTP 500")

        let validation = NetworkError.httpStatus(422, Data(#"{"detail":[{"loc":["body"],"msg":"bad"}]}"#.utf8))
        #expect(validation.errorDescription == "Server returned HTTP 422")
    }
}

struct MockDataServiceTests {
    @Test func radioStoryDemoIsIdempotent() async throws {
        let mock = MockDataService(latency: .zero)
        let before = await mock.currentGraph()

        let first = await mock.simulateIngestionOfRadioStory()
        let second = await mock.simulateIngestionOfRadioStory()
        let after = await mock.currentGraph()

        #expect(first.memory.id == second.memory.id)
        #expect(after.memories.count == before.memories.count + 1)
        #expect(after.sparks.count == before.sparks.count + 1)
        #expect(second.sparks.map(\.id) == first.sparks.map(\.id))
    }

    @Test func radioStorySparksAlex() async {
        let result = await MockDataService(latency: .zero).simulateIngestionOfRadioStory()
        #expect(result.sparks.map(\.targetMemberID) == [MockIDs.alex])
        #expect(result.newConnections.map(\.toMemberID) == [MockIDs.alex])
    }
}
