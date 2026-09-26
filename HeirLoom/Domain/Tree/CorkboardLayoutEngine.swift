import SwiftUI

/// Computes auto-orienting 2D corkboard coordinates and conspiracy red twine strings
/// for family members, placing Generation 1 at the top and propagating downwards.
public struct CorkboardLayoutEngine: Sendable {
    public let cardWidth: CGFloat
    public let cardHeight: CGFloat
    public let horizontalGap: CGFloat
    public let spouseGap: CGFloat
    public let tierHeight: CGFloat
    public let topPadding: CGFloat
    public let leftPadding: CGFloat

    public init(
        cardWidth: CGFloat = 150.0,
        cardHeight: CGFloat = 180.0,
        horizontalGap: CGFloat = 50.0,
        spouseGap: CGFloat = 26.0,
        tierHeight: CGFloat = 260.0,
        topPadding: CGFloat = 90.0,
        leftPadding: CGFloat = 100.0
    ) {
        self.cardWidth = cardWidth
        self.cardHeight = cardHeight
        self.horizontalGap = horizontalGap
        self.spouseGap = spouseGap
        self.tierHeight = tierHeight
        self.topPadding = topPadding
        self.leftPadding = leftPadding
    }

    /// Computes the layout state from an array of MemberDocuments.
    public func computeLayout(for rawMembers: [MemberDocument]) -> CorkboardLayoutState {
        guard !rawMembers.isEmpty else {
            return CorkboardLayoutState()
        }

        // 1. Reconcile bidirectional relationships (parents, children, spouse)
        let members = healRelationships(rawMembers)
        let byId: [String: MemberDocument] = Dictionary(uniqueKeysWithValues: members.map { ($0._id, $0) })

        // 2. Group members by generation tier
        var tiers: [Int: [MemberDocument]] = [:]
        for m in members {
            let tier = m.generationTier
            tiers[tier, default: []].append(m)
        }

        let sortedTierKeys = tiers.keys.sorted()
        let minTier = sortedTierKeys.first ?? 1
        let maxTier = sortedTierKeys.last ?? 1

        var positionedNodes: [String: CorkboardNode] = [:]
        var tierWidths: [Int: CGFloat] = [:]

        // 3. Layout each tier horizontally with spouse pairing
        for tier in sortedTierKeys {
            let tierMembers = tiers[tier] ?? []
            var visitedInTier: Set<String> = []
            var units: [[MemberDocument]] = []

            for m in tierMembers {
                if visitedInTier.contains(m._id) { continue }
                if let sId = m.spouseId,
                   let spouse = byId[sId],
                   spouse.generationTier == tier {
                    units.append([m, spouse])
                    visitedInTier.insert(m._id)
                    visitedInTier.insert(sId)
                } else {
                    units.append([m])
                    visitedInTier.insert(m._id)
                }
            }

            var currentX = leftPadding
            let y = topPadding + CGFloat(tier - minTier) * tierHeight

            for unit in units {
                if unit.count == 2 {
                    let m1 = unit[0]
                    let m2 = unit[1]

                    let node1 = makeNode(member: m1, tier: tier, x: currentX, y: y)
                    positionedNodes[m1._id] = node1
                    currentX += cardWidth + spouseGap

                    let node2 = makeNode(member: m2, tier: tier, x: currentX, y: y)
                    positionedNodes[m2._id] = node2
                    currentX += cardWidth + horizontalGap
                } else {
                    let m = unit[0]
                    let node = makeNode(member: m, tier: tier, x: currentX, y: y)
                    positionedNodes[m._id] = node
                    currentX += cardWidth + horizontalGap
                }
            }
            tierWidths[tier] = currentX
        }

        // 4. Center children under parent pins when feasible
        for tier in sortedTierKeys where tier > minTier {
            let tierMembers = tiers[tier] ?? []
            for m in tierMembers {
                let mid = m._id
                guard let currentNode = positionedNodes[mid] else { continue }
                let parentNodes = m.parents.compactMap { positionedNodes[$0] }
                if !parentNodes.isEmpty {
                    let avgParentX = parentNodes.map { $0.pinPoint.x }.reduce(0, +) / CGFloat(parentNodes.count)
                    let desiredX = avgParentX - (cardWidth / 2.0)

                    let sameTierNodes = positionedNodes.values.filter { $0.member.generationTier == tier && $0.id != mid }
                    let hasOverlap = sameTierNodes.contains { abs($0.x - desiredX) < (cardWidth + 16) }

                    if !hasOverlap && desiredX >= leftPadding {
                        var updatedNode = currentNode
                        updatedNode.position.x = desiredX
                        updatedNode.pinPoint.x = desiredX + (cardWidth / 2.0)
                        positionedNodes[mid] = updatedNode
                    }
                }
            }
        }

        // 5. Generate Connecting Strings (Red Twine)
        var strings: [CorkboardString] = []
        var pairedSpouses: Set<String> = []

        for (mid, node) in positionedNodes {
            let m = node.member

            // A. Spouse String (Taut Crimson String)
            if let spouseId = m.spouseId, let spouseNode = positionedNodes[spouseId] {
                let pairKey = [mid, spouseId].sorted().joined(separator: "_")
                if !pairedSpouses.contains(pairKey) {
                    pairedSpouses.insert(pairKey)
                    strings.append(
                        CorkboardString(
                            id: "str_spouse_\(pairKey)",
                            type: .spouse,
                            fromMemberId: mid,
                            toMemberId: spouseId,
                            fromPoint: node.pinPoint,
                            toPoint: spouseNode.pinPoint,
                            sagAmount: 6.0,
                            colorHex: "#e74c3c",
                            label: "Spouse"
                        )
                    )
                }
            }

            // B. Parent-Child Strings (Crimson Twine with natural gravity droop)
            for childId in m.children {
                if let childNode = positionedNodes[childId] {
                    strings.append(
                        CorkboardString(
                            id: "str_parent_\(mid)_\(childId)",
                            type: .parentChild,
                            fromMemberId: mid,
                            toMemberId: childId,
                            fromPoint: node.pinPoint,
                            toPoint: childNode.pinPoint,
                            sagAmount: 22.0,
                            colorHex: "#c0392b",
                            label: "Parent-Child"
                        )
                    )
                }
            }
        }

        let maxWidth = tierWidths.values.max() ?? 1200
        let canvasWidth = max(maxWidth + leftPadding, 1200.0)
        let canvasHeight = topPadding + CGFloat(maxTier - minTier + 1) * tierHeight + 160.0

        return CorkboardLayoutState(
            nodes: Array(positionedNodes.values),
            strings: strings,
            canvasSize: CGSize(width: canvasWidth, height: canvasHeight)
        )
    }

    private func makeNode(member: MemberDocument, tier: Int, x: CGFloat, y: CGFloat) -> CorkboardNode {
        let tilt = computeTilt(for: member._id)
        let pinColor = pickPinColor(tier: tier)
        let pinPoint = CGPoint(x: x + (cardWidth / 2.0), y: y + 14.0)

        return CorkboardNode(
            id: member._id,
            member: member,
            position: CGPoint(x: x, y: y),
            size: CGSize(width: cardWidth, height: cardHeight),
            pinPoint: pinPoint,
            rotationDegrees: tilt,
            pinColorHex: pinColor
        )
    }

    private func computeTilt(for id: String) -> Double {
        var hash = 0
        for char in id.utf8 {
            hash = (hash &* 31) &+ Int(char)
        }
        let angle = Double((abs(hash) % 55) - 27) * 0.1
        return (angle * 10).rounded() / 10
    }

    private func pickPinColor(tier: Int) -> String {
        switch tier {
        case 1: return "#e1b12c"  // Brass gold
        case 2: return "#e84118"  // Crimson red
        default: return "#00a8ff" // Cyan/silver
        }
    }

    private func healRelationships(_ members: [MemberDocument]) -> [MemberDocument] {
        var map = Dictionary(uniqueKeysWithValues: members.map { ($0._id, $0) })

        for (mid, m) in map {
            // Spouse bidirectional healing
            if let sId = m.spouseId, map[sId] != nil {
                if map[sId]?.spouseId != mid {
                    map[sId]?.spouseId = mid
                }
            }
            // Children -> Parents healing
            for cId in m.children where map[cId] != nil {
                if !(map[cId]?.parents.contains(mid) ?? false) {
                    map[cId]?.parents.append(mid)
                }
            }
            // Parents -> Children healing
            for pId in m.parents where map[pId] != nil {
                if !(map[pId]?.children.contains(mid) ?? false) {
                    map[pId]?.children.append(mid)
                }
            }
        }
        return Array(map.values)
    }
}
