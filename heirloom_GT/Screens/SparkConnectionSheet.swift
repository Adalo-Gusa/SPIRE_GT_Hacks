import SwiftUI

/// Presented when tapping an Intergenerational Spark notification or banner.
/// Shows the authentic connection between two family members across generations,
/// the story quote that triggered the spark, and quick CTAs to call or chat with Loomie.
struct SparkConnectionSheet: View {
    let spark: SparkDocument
    var onTalkToLoomie: ((String) -> Void)? = nil

    @EnvironmentObject private var archive: FamilyArchive
    @Environment(\.dismiss) private var dismiss

    @State private var showingCallAlert = false

    private var elder: MemberDocument? {
        archive.members.first { $0._id == spark.elderId }
    }

    private var targetMember: MemberDocument? {
        archive.members.first { $0._id == spark.targetMemberId }
    }

    private var elderName: String {
        elder?.name ?? "Grandpa Joe"
    }

    private var targetName: String {
        targetMember?.name ?? "Alex"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    // 1. Spark Badge & Header
                    sparkHeader

                    // 2. Intergenerational Bridge (Two Avatars + Connection String)
                    intergenerationalBridgeCard

                    // 3. Heartwarming Spark Story Card
                    sparkStoryCard

                    // 4. Action Buttons
                    actionButtons
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 36)
            }
            .background { CorkboardBackground() }
            .navigationTitle("Family Spark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(HeirloomColor.plum.opacity(0.8))
                    }
                }
            }
            .alert("Call \(elderName)?", isPresented: $showingCallAlert) {
                Button("Call", role: .none) {
                    initiatePhoneCall()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Would you like to give \(elderName) a call now to hear more about this story?")
            }
        }
    }

    // MARK: - Header

    private var sparkHeader: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(HeirloomColor.rose)
                Text("Connection Discovered")
                    .font(.heirloomDisplay(24, relativeTo: .title2))
                    .foregroundStyle(HeirloomColor.plum)
            }

            Text("The archiving agent found a shared spark across generations")
                .font(.footnote)
                .foregroundStyle(HeirloomColor.tabLabel)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Bridge Card

    private var intergenerationalBridgeCard: some View {
        HStack(spacing: 0) {
            // Elder
            VStack(spacing: 8) {
                avatarView(member: elder, fallbackName: elderName)
                Text(elderName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HeirloomColor.plum)
                if let gen = elder?.generationTier {
                    Text("Gen \(gen)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(HeirloomColor.rose)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(HeirloomColor.rose.opacity(0.15), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)

            // Connection String / Sparkles
            VStack(spacing: 4) {
                ZStack {
                    Rectangle()
                        .fill(HeirloomColor.rose.opacity(0.6))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)

                    Image(systemName: "bolt.heart.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(HeirloomColor.rose)
                        .background(
                            Circle()
                                .fill(HeirloomColor.polaroidFrame)
                                .frame(width: 32, height: 32)
                        )
                }

                Text(spark.matchedPassion)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(HeirloomColor.plum)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(HeirloomColor.board, in: Capsule())
            }
            .frame(maxWidth: .infinity)

            // Target Member
            VStack(spacing: 8) {
                avatarView(member: targetMember, fallbackName: targetName)
                Text(targetName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HeirloomColor.plum)
                if let gen = targetMember?.generationTier {
                    Text("Gen \(gen)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(HeirloomColor.plum)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(HeirloomColor.plum.opacity(0.15), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 14)
        .background(HeirloomColor.polaroidFrame, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(HeirloomColor.labelBorder, lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 6, x: 2, y: 3)
    }

    private func avatarView(member: MemberDocument?, fallbackName: String) -> some View {
        Image(member?.placeholderImageName ?? "guy")
            .resizable()
            .scaledToFill()
            .frame(width: 64, height: 64)
            .background(HeirloomColor.polaroidPhoto)
            .clipShape(Circle())
            .overlay(Circle().stroke(HeirloomColor.rose.opacity(0.4), lineWidth: 2))
            .shadow(color: .black.opacity(0.15), radius: 3, x: 1, y: 2)
    }

    // MARK: - Spark Story Card

    private var sparkStoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "quote.opening")
                    .font(.subheadline)
                    .foregroundStyle(HeirloomColor.rose)
                Text("Oral Archive Connection")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HeirloomColor.plum)
            }

            Text(spark.sparkMessage)
                .font(.heirloomSerif(16, relativeTo: .body))
                .foregroundStyle(HeirloomColor.plum)
                .lineSpacing(4)

            Divider()

            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.subheadline)
                    .foregroundStyle(HeirloomColor.rose)
                Text(spark.ctaAction)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HeirloomColor.plum)
            }
        }
        .padding(18)
        .background(HeirloomColor.polaroidFrame, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(HeirloomColor.labelBorder, lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.1), radius: 5, x: 2, y: 3)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Call Elder Button
            Button {
                showingCallAlert = true
            } label: {
                Label("Give \(elderName) a Call", systemImage: "phone.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(HeirloomColor.rose)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: HeirloomColor.rose.opacity(0.3), radius: 4, y: 2)

            // Chat with Loomie Button
            Button {
                dismiss()
                let prompt = "Loomie, tell me more about \(elderName)'s memory about \(spark.matchedPassion)!"
                onTalkToLoomie?(prompt)
            } label: {
                Label("Chat with Loomie about this", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .tint(HeirloomColor.plum)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func initiatePhoneCall() {
        // Attempt opening tel URL or simulate prompt
        let sanitized = "18005550199"
        if let url = URL(string: "tel://\(sanitized)"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}
