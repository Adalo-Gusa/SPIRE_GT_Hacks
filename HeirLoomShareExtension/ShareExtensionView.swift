import SwiftUI

/// Custom SwiftUI card UI presented within the iOS Share Sheet.
/// Matches HeirLoom's Figma theme: corkboard palette, Polaroid frame, pushpin, and plum accents.
public struct ShareExtensionView: View {
    public let initialImage: UIImage?
    public let initialURL: URL?
    public let initialCaption: String
    public var onSave: (SharedPostPayload, Data?) -> Void
    public var onCancel: () -> Void

    @State private var caption: String
    @State private var selectedAuthorId: String = "member_alex"
    @State private var isSaving: Bool = false

    private let familyMembers = [
        ("member_alex", "Alex Clarke (Grandchild, Gen 3)"),
        ("member_chloe", "Chloe Clarke (Grandchild, Gen 3)"),
        ("member_marcus", "Marcus Clarke (Son, Gen 2)"),
        ("member_sarah", "Sarah Clarke (Daughter, Gen 2)"),
        ("member_grandpa_joe", "Grandpa Joe (Elder, Gen 1)"),
        ("member_grandma_eleanor", "Grandma Eleanor (Elder, Gen 1)")
    ]

    public init(
        initialImage: UIImage?,
        initialURL: URL?,
        initialCaption: String,
        onSave: @escaping (SharedPostPayload, Data?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialImage = initialImage
        self.initialURL = initialURL
        self.initialCaption = initialCaption
        self.onSave = onSave
        self.onCancel = onCancel
        _caption = State(initialValue: initialCaption)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    // 1. Polaroid Card with Image & Pushpin
                    VStack(spacing: 12) {
                        // Pushpin
                        Circle()
                            .fill(Color(red: 0.80, green: 0.28, blue: 0.44)) // Rose pin
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1.5))
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 2)
                            .padding(.top, 4)

                        // Photo Well
                        if let image = initialImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 220)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        } else if let url = initialURL {
                            VStack(spacing: 8) {
                                Image(systemName: "link.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(Color(red: 0.29, green: 0.19, blue: 0.27))
                                Text(url.host ?? "Instagram Post")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(red: 0.47, green: 0.33, blue: 0.44))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 120)
                            .background(Color(red: 0.94, green: 0.89, blue: 0.84))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        // Caption Editor
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Caption / Story")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color(red: 0.47, green: 0.33, blue: 0.44))

                            TextField("Add a note about this moment...", text: $caption, axis: .vertical)
                                .lineLimit(3...5)
                                .font(.body)
                                .foregroundStyle(Color(red: 0.29, green: 0.19, blue: 0.27))
                                .padding(10)
                                .background(Color(red: 0.94, green: 0.89, blue: 0.84), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding(16)
                    .background(Color(red: 0.89, green: 0.81, blue: 0.72)) // Polaroid frame
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 4, y: 5)

                    // 2. Member Selector Card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sharing to HeirLoom as:")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color(red: 0.29, green: 0.19, blue: 0.27))

                        Menu {
                            ForEach(familyMembers, id: \.0) { id, name in
                                Button {
                                    selectedAuthorId = id
                                } label: {
                                    HStack {
                                        Text(name)
                                        if id == selectedAuthorId {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text(selectedAuthorName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color(red: 0.29, green: 0.19, blue: 0.27))
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(Color(red: 0.47, green: 0.33, blue: 0.44))
                            }
                            .padding(12)
                            .background(Color(red: 0.94, green: 0.89, blue: 0.84), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(16)
                    .background(Color(red: 0.89, green: 0.81, blue: 0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 3, y: 4)

                    // 3. Save Button
                    Button {
                        handleSave()
                    } label: {
                        HStack(spacing: 8) {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "pin.fill")
                                    .font(.caption.weight(.bold))
                                Text("Pin to Family Feed")
                                    .font(.headline.weight(.bold))
                            }
                        }
                        .foregroundStyle(Color(red: 0.94, green: 0.89, blue: 0.84))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(red: 0.29, green: 0.19, blue: 0.27), in: Capsule())
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 2, y: 4)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(red: 0.82, green: 0.71, blue: 0.59).ignoresSafeArea())
            .navigationTitle("Share to HeirLoom")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundStyle(Color(red: 0.29, green: 0.19, blue: 0.27))
                }
            }
        }
    }

    private var selectedAuthorName: String {
        familyMembers.first { $0.0 == selectedAuthorId }?.1 ?? "Alex Clarke"
    }

    private func handleSave() {
        isSaving = true

        let imageData = initialImage?.jpegData(compressionQuality: 0.85)
        let authorSimpleName = selectedAuthorName.components(separatedBy: " (").first ?? "Alex Clarke"

        let payload = SharedPostPayload(
            source: "instagram",
            caption: caption,
            postURL: initialURL?.absoluteString,
            authorId: selectedAuthorId,
            authorName: authorSimpleName,
            timestamp: Date(),
            status: .pending
        )

        onSave(payload, imageData)
    }
}
