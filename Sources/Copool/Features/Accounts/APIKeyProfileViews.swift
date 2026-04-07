import SwiftUI

struct AuthModeSwitcher: View {
    @Binding var activeMode: ActiveAuthMode

    var body: some View {
        HStack(spacing: 0) {
            modeButton(.chatgpt, title: L10n.tr("auth_mode.chatgpt"))
            modeButton(.apiKey, title: L10n.tr("auth_mode.api_key"))
        }
        .background { containerBackground }
        .overlay {
            Capsule()
                .strokeBorder(separatorColor, lineWidth: 1)
        }
        .clipShape(Capsule())
    }

    private func modeButton(_ mode: ActiveAuthMode, title: String) -> some View {
        Button {
            activeMode = mode
        } label: {
            Text(title)
                .font(.system(size: 13, weight: activeMode == mode ? .semibold : .medium))
                .foregroundStyle(activeMode == mode ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.plain)
        .background {
            if activeMode == mode {
                selectedBackground
                    .padding(3)
            }
        }
    }

    @ViewBuilder
    private var containerBackground: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular, in: .capsule)
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private var selectedBackground: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(
                    .regular
                        .tint(Color.accentColor.opacity(0.16))
                        .interactive(),
                    in: .capsule
                )
        } else {
            Capsule()
                .fill(.regularMaterial)
                .overlay {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.12))
                }
        }
    }

    private var separatorColor: Color {
        #if canImport(AppKit)
        Color(nsColor: .separatorColor).opacity(0.9)
        #else
        Color.secondary.opacity(0.22)
        #endif
    }
}

// MARK: - API Key Profile List

struct APIKeyProfileListView: View {
    @ObservedObject var model: AccountsPageModel
    var onAddProfile: () -> Void
    var onEditProfile: (APIKeyProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.tr("apikey.section.title"))
                    .font(.headline)
                Spacer()
                Button(L10n.tr("apikey.action.add_profile")) {
                    onAddProfile()
                }
                .copoolActionButtonStyle(prominent: true)
            }

            if model.apiKeyProfiles.isEmpty {
                VStack(spacing: 8) {
                    Text(L10n.tr("apikey.empty.title"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(L10n.tr("apikey.empty.message"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(model.apiKeyProfiles) { profile in
                        APIKeyProfileCardView(
                            profile: profile,
                            isSwitching: model.switchingAPIKeyProfileID == profile.id,
                            onSwitch: {
                                Task { await model.switchToAPIKeyProfile(id: profile.id) }
                            },
                            onEdit: {
                                onEditProfile(profile)
                            },
                            onDelete: {
                                Task { await model.deleteAPIKeyProfile(id: profile.id) }
                            }
                        )
                    }
                }
            }
        }
        .padding(LayoutRules.pagePadding)
        .task(id: "initial-load") {
            guard model.apiKeyProfiles.isEmpty else { return }
            await model.loadAPIKeyProfiles()
        }
    }
}

// MARK: - API Key Profile Card

struct APIKeyProfileCardView: View {
    let profile: APIKeyProfile
    let isSwitching: Bool
    let onSwitch: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(profile.label)
                            .font(.headline)
                        if profile.isCurrent {
                            currentBadge
                        }
                    }
                    Text(profile.providerLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                actionButtons
            }

            VStack(alignment: .leading, spacing: 6) {
                detailRow(L10n.tr("apikey.field.model"), value: profile.model)
                detailRow(L10n.tr("apikey.field.base_url"), value: profile.baseURL)
                detailRow(L10n.tr("apikey.field.api_key"), value: profile.maskedAPIKey)
                if let effort = profile.reasoningEffort, !effort.isEmpty {
                    detailRow(L10n.tr("apikey.field.reasoning_effort"), value: effort)
                }
                detailRow(L10n.tr("apikey.field.wire_api"), value: profile.wireAPI)
            }
        }
        .padding(14)
        .cardSurface(cornerRadius: LayoutRules.cardRadius)
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
                .copoolActionButtonStyle(prominent: true)
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

// MARK: - API Key Profile Editor

struct APIKeyProfileEditorView: View {
    let existingProfile: APIKeyProfile?
    let onSave: (APIKeyProfile) -> Void
    let onCancel: () -> Void

    @State private var label: String = ""
    @State private var providerLabel: String = ""
    @State private var apiKey: String = ""
    @State private var baseURL: String = ""
    @State private var model: String = ""
    @State private var reasoningEffort: String = ""
    @State private var wireAPI: String = "responses"

    private var isEditing: Bool { existingProfile != nil }

    private var canSave: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isEditing ? L10n.tr("apikey.editor.title_edit") : L10n.tr("apikey.editor.title_new"))
                    .font(.headline)
                Spacer()
                Button(L10n.tr("common.cancel"), action: onCancel)
                    .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    editorField(L10n.tr("apikey.field.label"), text: $label, placeholder: "My API Profile")
                    editorField(L10n.tr("apikey.field.provider"), text: $providerLabel, placeholder: "OpenAI")
                    editorField(L10n.tr("apikey.field.api_key"), text: $apiKey, placeholder: "sk-...")
                    editorField(L10n.tr("apikey.field.base_url"), text: $baseURL, placeholder: "https://api.openai.com/v1")
                    editorField(L10n.tr("apikey.field.model"), text: $model, placeholder: "gpt-4o")
                    editorField(L10n.tr("apikey.field.reasoning_effort"), text: $reasoningEffort, placeholder: L10n.tr("common.optional"))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.tr("apikey.field.wire_api"))
                            .font(.subheadline.weight(.medium))
                        Picker("", selection: $wireAPI) {
                            Text("Responses API").tag("responses")
                            Text("Chat Completions API").tag("chat")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Spacer()
                Button(L10n.tr("common.cancel"), action: onCancel)
                Button(L10n.tr("common.save")) {
                    let profile = APIKeyProfile(
                        id: existingProfile?.id ?? UUID().uuidString,
                        label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                        providerLabel: providerLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                        apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                        baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                        model: model.trimmingCharacters(in: .whitespacesAndNewlines),
                        reasoningEffort: reasoningEffort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? nil : reasoningEffort.trimmingCharacters(in: .whitespacesAndNewlines),
                        wireAPI: wireAPI,
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
        .frame(minWidth: 400, minHeight: 500)
        .onAppear {
            if let existing = existingProfile {
                label = existing.label
                providerLabel = existing.providerLabel
                apiKey = existing.apiKey
                baseURL = existing.baseURL
                model = existing.model
                reasoningEffort = existing.reasoningEffort ?? ""
                wireAPI = existing.wireAPI
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
