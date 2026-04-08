import SwiftUI

struct ClaudePageView: View {
    @ObservedObject var model: ClaudePageModel
    @State private var isShowingEditor = false
    @State private var editingProfile: ClaudeAPIKeyProfile?

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L10n.tr("claude.section.title"))
                            .font(.headline)
                        Spacer()
                        Button(L10n.tr("claude.action.add_profile")) {
                            editingProfile = nil
                            isShowingEditor = true
                        }
                        .codeXPoolActionButtonStyle(prominent: true)
                    }

                    if model.profiles.isEmpty {
                        VStack(spacing: 8) {
                            Text(L10n.tr("claude.empty.title"))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(L10n.tr("claude.empty.message"))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        LazyVGrid(
                            columns: [
                                GridItem(.fixed(LayoutRules.accountsCardWidth), spacing: LayoutRules.accountsRowSpacing, alignment: .top),
                                GridItem(.fixed(LayoutRules.accountsCardWidth), spacing: LayoutRules.accountsRowSpacing, alignment: .top)
                            ],
                            alignment: .leading,
                            spacing: LayoutRules.accountsRowSpacing
                        ) {
                            ForEach(model.profiles) { profile in
                                ClaudeAPIKeyCardView(
                                    profile: profile,
                                    isSwitching: model.switchingProfileID == profile.id,
                                    onSwitch: {
                                        Task { await model.switchToProfile(id: profile.id) }
                                    },
                                    onEdit: {
                                        editingProfile = profile
                                        isShowingEditor = true
                                    },
                                    onDelete: {
                                        Task { await model.deleteProfile(id: profile.id) }
                                    }
                                )
                                .frame(width: LayoutRules.accountsCardWidth)
                            }
                        }
                    }
                }
                .padding(LayoutRules.pagePadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .task {
                await model.loadIfNeeded()
            }

            if isShowingEditor {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { isShowingEditor = false }

                ClaudeAPIKeyEditorView(
                    existingProfile: editingProfile,
                    onSave: { profile in
                        let isEditing = editingProfile != nil
                        isShowingEditor = false
                        Task { await model.saveProfile(profile, isEditing: isEditing) }
                    },
                    onCancel: { isShowingEditor = false }
                )
                .frame(width: 420, height: 420)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isShowingEditor)
    }
}

// MARK: - Claude API Key Card

private struct ClaudeAPIKeyCardView: View {
    let profile: ClaudeAPIKeyProfile
    let isSwitching: Bool
    let onSwitch: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(profile.label)
                            .font(.headline)
                        if profile.isCurrent {
                            currentBadge
                        }
                    }
                    if !profile.model.isEmpty {
                        Text(profile.model)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                actionButtons
            }

            VStack(alignment: .leading, spacing: 4) {
                detailRow(L10n.tr("claude.field.base_url"), value: profile.baseURL)
                detailRow(L10n.tr("claude.field.api_key"), value: profile.maskedAPIKey)
            }
        }
        .padding(10)
        .accountCardSurface(cornerRadius: 12)
    }

    private var currentBadge: some View {
        Text(L10n.tr("apikey.badge.current"))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if !profile.isCurrent {
                Button {
                    onSwitch()
                } label: {
                    if isSwitching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(L10n.tr("apikey.action.switch"))
                    }
                }
                .codeXPoolActionButtonStyle(prominent: true)
                .disabled(isSwitching)
            }
            Menu {
                Button(L10n.tr("common.edit"), action: onEdit)
                Button(L10n.tr("common.delete"), role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer()
        }
    }
}

// MARK: - Claude API Key Editor

private struct ClaudeAPIKeyEditorView: View {
    let existingProfile: ClaudeAPIKeyProfile?
    let onSave: (ClaudeAPIKeyProfile) -> Void
    let onCancel: () -> Void

    @State private var label: String = ""
    @State private var apiKey: String = ""
    @State private var baseURL: String = ""
    @State private var model: String = ""

    private var isEditing: Bool { existingProfile != nil }

    private var canSave: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isEditing ? L10n.tr("claude.editor.title_edit") : L10n.tr("claude.editor.title_new"))
                    .font(.headline)
                Spacer()
                Button(L10n.tr("common.cancel"), action: onCancel)
                    .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    editorField(L10n.tr("claude.field.label"), text: $label, placeholder: "My Claude Profile")
                    editorField(L10n.tr("claude.field.api_key"), text: $apiKey, placeholder: "sk-ant-...")
                    editorField(L10n.tr("claude.field.base_url"), text: $baseURL, placeholder: "https://api.anthropic.com")
                    editorField(L10n.tr("claude.field.model"), text: $model, placeholder: L10n.tr("common.optional"))
                }
                .padding()
            }

            Divider()

            HStack {
                Spacer()
                Button(L10n.tr("common.cancel"), action: onCancel)
                Button(L10n.tr("common.save")) {
                    let profile = ClaudeAPIKeyProfile(
                        id: existingProfile?.id ?? UUID().uuidString,
                        label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                        apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                        baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                        model: model.trimmingCharacters(in: .whitespacesAndNewlines),
                        addedAt: existingProfile?.addedAt ?? 0,
                        updatedAt: 0
                    )
                    onSave(profile)
                }
                .disabled(!canSave)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 400)
        .onAppear {
            if let existing = existingProfile {
                label = existing.label
                apiKey = existing.apiKey
                baseURL = existing.baseURL
                model = existing.model
            }
        }
    }

    private func editorField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.medium))
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
