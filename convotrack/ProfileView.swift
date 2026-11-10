import SwiftUI
import PhotosUI
import UserNotifications
import ClerkKit

struct ProfileView: View {
    @Environment(Clerk.self) private var clerk
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var rideSession: RideRealtimeSession
    @EnvironmentObject private var store: MembershipStore
    @Environment(\.dismiss) private var dismiss
    @State private var userProfile: UserMeResponse? = nil
    @State private var completedRides: [HistoryRide]? = nil
    @State private var isSigningOut = false
    @EnvironmentObject private var paywall: PaywallPresenter
    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String?
    @State private var showEditProfile = false
    @State private var notifPrefs = APIClient.NotificationPreferences(rideUpdates: true, regroup: true)
    @State private var notifDenied = false
    @Environment(\.scenePhase) private var scenePhase

    /// The name other riders see. Clerk is the source of truth (an edit writes it there and the
    /// Clerk user is reloaded), so it updates the moment Edit Profile saves.
    private var displayName: String {
        let parts = [clerk.user?.firstName, clerk.user?.lastName]
            .compactMap { $0 }.filter { !$0.isEmpty }
        let name = parts.joined(separator: " ")
        if !name.isEmpty { return name }
        if let server = userProfile?.name, !server.isEmpty, server != "Unknown" { return server }
        return clerk.user?.username ?? "Rider"
    }

    private var avatarUrl: URL? {
        guard let str = clerk.user?.imageUrl, !str.isEmpty else { return nil }
        return URL(string: str)
    }

    /// The address the rider signed in with. Read-only: it identifies the account, it isn't a setting.
    private var signInEmail: String? {
        clerk.user?.primaryEmailAddress?.emailAddress
            ?? clerk.user?.externalAccounts.first?.emailAddress
    }

    /// Names the method, not just "Signed in" (HIG Managing accounts: identify the authentication method).
    private var signInMethod: LocalizedStringKey {
        let providers = clerk.user?.externalAccounts.map { $0.provider.lowercased() } ?? []
        if providers.contains(where: { $0.contains("google") }) { return "Signed in with Google" }
        if providers.contains(where: { $0.contains("apple") }) { return "Signed in with Apple" }
        return "Signed in with email"
    }

    private var connectionState: DSConnectionState {
        switch rideSession.connectionState {
        case .connected: .connected
        case .reconnecting: .reconnecting
        case .disconnected: .offline
        }
    }

    // Stats come from the completed-ride list (same call History makes).
    private var rideCount: String { completedRides.map { String($0.count) } ?? "--" }
    private var totalKm: String {
        completedRides.map { String(format: "%.0f", $0.reduce(0) { $0 + $1.distanceMeters / 1000 }) } ?? "--"
    }
    private var ridesLed: String { completedRides.map { String($0.filter { $0.isLeader == true }.count) } ?? "--" }

    var body: some View {
        ZStack {
            DSScreenBackground()
            ScrollView {
                VStack(spacing: DS.Space.sectionGap) {
                    identity
                    stats
                    DSPromoBanner(
                        eyebrow: "ConvoTrack Pro",
                        message: promoMessage,
                        actionTitle: store.isPremium ? "Active" : "Go Pro",
                        isSubscribed: store.isPremium,
                        goProStyle: true
                    ) { paywall.present(.profile) }

                    notificationsSection

                    DSSettingsGroup {
                        DSSettingsRow(systemImage: "creditcard", title: "Membership & Billing") { paywall.present(.profile) }
                        DSSettingsRow(systemImage: "hand.raised", title: "Privacy Policy", trailing: .externalLink) {
                            if let url = URL(string: AppURLs.privacyPolicy) { openURL(url) }
                        }
                        DSSettingsRow(systemImage: "doc.text", title: "Terms of Service", trailing: .externalLink, showsDivider: false) {
                            if let url = URL(string: AppURLs.termsOfService) { openURL(url) }
                        }
                    }

                    VStack(alignment: .leading, spacing: DS.Space.p2) {
                        Text("Account")
                            .dsText(.bodyStrong)
                            .foregroundStyle(DS.Text.primary)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.horizontal, DS.Space.p1)
                        DSSettingsGroup {
                            signedInRow
                            DSSettingsRow(
                                systemImage: "rectangle.portrait.and.arrow.right",
                                title: isSigningOut ? "Signing out…" : "Sign Out",
                                trailing: .none,
                                isDestructive: true
                            ) { signOut() }
                            .disabled(isSigningOut || isDeletingAccount)
                            // Delete Account — required by App Store Guideline 5.1.1
                            DSSettingsRow(
                                systemImage: "trash",
                                title: isDeletingAccount ? "Deleting…" : "Delete Account",
                                trailing: .none,
                                isDestructive: true,
                                showsDivider: false
                            ) { showDeleteAccountConfirm = true }
                            .disabled(isDeletingAccount || isSigningOut)
                        }
                        if let deleteError { DSInlineError(message: LocalizedStringKey(deleteError)) }
                    }
                }
                .padding(.horizontal, DS.Space.screenInset)
                .padding(.top, DS.Space.p2)
                .padding(.bottom, DS.Space.sectionGap)
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .dsTransparentNavigationBar()
        // Hidden for now: the top-right slot is reserved for a notification bell.
        // .toolbar {
        //     // The connection indicator only means something while a ride session exists.
        //     if appState.currentRideId != nil {
        //         ToolbarItem(placement: .topBarTrailing) {
        //             DSConnectionStatusButton(state: connectionState)
        //         }
        //         .sharedBackgroundVisibility(.hidden)
        //     }
        // }
        .task {
            async let me = try? await APIClient.shared.fetchMe()
            async let history = try? await APIClient.shared.getMyRides(statuses: APIClient.RideStatusFilter.completed)
            if let p = await me { userProfile = p }
            if let h = await history { completedRides = h.filter { $0.status == "COMPLETED" } }
        }
        .task {
            if let prefs = try? await APIClient.shared.getNotificationPreferences() { notifPrefs = prefs }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            notifDenied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
        }
        .sheet(isPresented: $showEditProfile) {
            EditProfileSheet(
                userId:                     clerk.user?.id ?? displayName,
                initialName:                displayName,
                currentAvatarURL:           avatarUrl,
                initialUsername:            userProfile?.username ?? "",
                initialPhone:               userProfile?.phone ?? "",
                initialPhoneVisible:        userProfile?.phoneVisible ?? false,
                initialEmailContact:        userProfile?.emailContact ?? "",
                initialEmailContactVisible: userProfile?.emailContactVisible ?? false,
                onSaved: { _ in
                    Task {
                        if let p = try? await APIClient.shared.fetchMe() { userProfile = p }
                    }
                }
            )
        }
        .alert("Delete Your Account?", isPresented: $showDeleteAccountConfirm) {
            Button("Delete", role: .destructive) { Task { await deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete your account and all ride history. Active subscriptions must be cancelled separately in Settings > Apple ID > Subscriptions. This cannot be undone.")
        }
    }

    /// The trial leads; the generic pitch is only for riders with no enforced trial.
    private var promoMessage: LocalizedStringKey {
        switch store.access {
        case .pro:
            return "Your membership is active"
        case .trial:
            guard let days = store.trialDaysLeft, days > 1 else { return "Your free trial ends today" }
            return "\(days) days left in your free trial"
        case .trialExpired:
            return "Your free trial has ended. Go Pro to keep riding."
        case .free:
            return "Unlimited rides & bigger packs"
        }
    }

    // MARK: - Sections

    private var identity: some View {
        VStack(spacing: DS.Space.p3) {
            // The photo is the obvious place to change the photo; it opens the same sheet.
            Button { showEditProfile = true } label: {
                DSAvatar(
                    name: displayName,
                    id: clerk.user?.id ?? displayName,
                    imageURL: avatarUrl,
                    size: DS.AvatarSize.xxl,
                    highlightRing: DS.Accent.base
                )
                .overlay(alignment: .bottomTrailing) { AvatarEditBadge() }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change profile photo")
            // The sheet seeds its fields from `/users/me`; opened before that answers, Save would
            // send blank visibility toggles and switch them off.
            .disabled(userProfile == nil)
            HStack(spacing: DS.Space.p2) {
                Text(displayName)
                    .dsText(.titleLarge)
                    .foregroundStyle(DS.Text.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                DSSquareIconButton(systemImage: "pencil", label: "Edit profile") { showEditProfile = true }
                    .disabled(userProfile == nil)
            }
            if let username = userProfile?.username, !username.isEmpty {
                Text(verbatim: "@\(username)")
                    .dsText(.body)
                    .foregroundStyle(DS.Text.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// First row of the Account group: how and as whom the rider is signed in.
    private var signedInRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.p4) {
                Image(systemName: "person.crop.circle")
                    .dsIcon(DS.IconSize.md)
                    .foregroundStyle(DS.Text.secondary.base)
                    .frame(width: DS.IconSize.lg)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(signInMethod)
                        .dsText(.bodySmall)
                        .foregroundStyle(DS.Text.secondary)
                    Text(verbatim: signInEmail ?? "—")
                        .dsText(.body)
                        .foregroundStyle(DS.Text.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Space.p4)
            .padding(.vertical, 12)
            .frame(minHeight: 64)
            .accessibilityElement(children: .combine)
            DSDivider().padding(.leading, 52)
        }
    }

    /// Three equal columns; one per row at accessibility sizes.
    private var stats: some View {
        DSAdaptiveStack(spacing: DS.Space.p3, verticalAlignment: .top) {
            DSStatTile(systemImage: "flag", label: "Rides", value: rideCount, fillsWidth: true, showsIcon: false)
            DSStatTile(systemImage: "point.topleft.down.to.point.bottomright.curvepath", label: "Total km", value: totalKm, fillsWidth: true, showsIcon: false)
            DSStatTile(systemImage: "person.fill", label: "Rides led", value: ridesLed, fillsWidth: true, showsIcon: false)
        }
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.p2) {
            Text("Notifications")
                .dsText(.bodyStrong)
                .foregroundStyle(DS.Text.primary)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, DS.Space.p1)
            DSSettingsGroup {
                notificationToggle("Ride updates", systemImage: "bell", isOn: notifPrefs.rideUpdates) {
                    setPref(\.rideUpdates, $0)
                }
                notificationToggle("Regroup calls", systemImage: "arrow.triangle.merge", isOn: notifPrefs.regroup) {
                    setPref(\.regroup, $0)
                }
                HStack(spacing: DS.Space.p4) {
                    Image(systemName: "exclamationmark.triangle")
                        .dsIcon(DS.IconSize.md)
                        .foregroundStyle(DS.Text.secondary.base)
                        .frame(width: DS.IconSize.lg)
                        .accessibilityHidden(true)
                    Text("Safety alerts, always on").dsText(.body).foregroundStyle(DS.Text.secondary.base)
                    Spacer(minLength: DS.Space.p2)
                }
                .padding(.horizontal, DS.Space.p4)
                .padding(.vertical, 14)
                .frame(minHeight: 56)
                .accessibilityElement(children: .combine)
            }
            if notifDenied {
                Text("Notifications are turned off for ConvoTrack in system settings.")
                    .dsText(.helper)
                    .foregroundStyle(DS.Text.secondary)
                    .padding(.horizontal, DS.Space.p1)
                DSSettingsGroup {
                    DSSettingsRow(systemImage: "gearshape", title: "Open Settings", trailing: .externalLink, showsDivider: false) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            }
        }
    }

    private func notificationToggle(_ title: LocalizedStringKey, systemImage: String, isOn: Bool,
                                    set: @escaping (Bool) -> Void) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.p4) {
                Image(systemName: systemImage)
                    .dsIcon(DS.IconSize.md)
                    .foregroundStyle(DS.Text.secondary.base)
                    .frame(width: DS.IconSize.lg)
                    .accessibilityHidden(true)
                Toggle(isOn: Binding(get: { isOn }, set: set)) {
                    Text(title).dsText(.body).foregroundStyle(DS.Text.primary)
                }
                .tint(DS.Accent.base)
            }
            .padding(.horizontal, DS.Space.p4)
            .padding(.vertical, 8)
            .frame(minHeight: 56)
            DSDivider().padding(.leading, 52)
        }
    }

    /// Optimistic: flip now, PUT, revert on failure.
    private func setPref(_ key: WritableKeyPath<APIClient.NotificationPreferences, Bool>, _ value: Bool) {
        let previous = notifPrefs[keyPath: key]
        notifPrefs[keyPath: key] = value
        Task {
            do {
                let saved = key == \.rideUpdates
                    ? try await APIClient.shared.updateNotificationPreferences(rideUpdates: value)
                    : try await APIClient.shared.updateNotificationPreferences(regroup: value)
                // Apply only this key, and only if no newer toggle has superseded it.
                if notifPrefs[keyPath: key] == value { notifPrefs[keyPath: key] = saved[keyPath: key] }
            } catch {
                if notifPrefs[keyPath: key] == value { notifPrefs[keyPath: key] = previous }
            }
        }
    }

    private func signOut() {
        Task {
            isSigningOut = true
            appState.currentRideId = nil
            appState.inviteCode = nil
            appState.currentRide = nil
            Analytics.reset()
            await PushNotifications.unregister()
            try? await Clerk.shared.auth.signOut()
            await ImageCache.clearEverything()
            // Signing out is the one moment we know the rider may want a different
            // account next time; it arms the cookie-free web session that lets
            // Google ask which one. See `WebSignInSession`.
            WebSignInSession.needsAccountChoice = true
            dismiss()
        }
    }
}

// MARK: - Account Actions

extension ProfileView {
    func deleteAccount() async {
        isDeletingAccount = true
        deleteError = nil
        do {
            try await clerk.user?.delete()
            await ImageCache.clearEverything()
            appState.currentRideId = nil
            appState.inviteCode = nil
            appState.currentRide = nil
            dismiss()
        } catch {
            // Shown inline under the Account group (spec: deleteAccountDialog showsInlineError).
            deleteError = error.riderMessage
            isDeletingAccount = false
        }
    }
}

// MARK: - Edit Profile Sheet

/// Camera badge on an avatar that opens photo editing. Decorative; the button around it is labelled.
struct AvatarEditBadge: View {
    var body: some View {
        Image(systemName: "camera.fill")
            .dsIcon(DS.IconSize.sm, weight: .semibold)
            .foregroundStyle(DS.Text.onAccent)
            .frame(width: 32, height: 32)
            .background(Circle().fill(DS.Accent.base))
            .overlay(Circle().stroke(DS.Background.base, lineWidth: 3))
            .offset(x: 2, y: 2)
            .accessibilityHidden(true)
    }
}

struct EditProfileSheet: View {
    /// What riders may call themselves; matches the server's `NAME_MAX_LENGTH`.
    static let nameMaxLength = 40

    let userId: String
    let initialName: String
    let currentAvatarURL: URL?
    let initialUsername: String
    let initialPhone: String
    let initialPhoneVisible: Bool
    let initialEmailContact: String
    let initialEmailContactVisible: Bool
    let onSaved: (UpdateProfileRequest) -> Void

    @Environment(Clerk.self) private var clerk
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var username: String
    @State private var phone: String
    @State private var phoneVisible: Bool
    @State private var emailContact: String
    @State private var emailContactVisible: Bool
    @State private var photoItem: PhotosPickerItem?
    /// The picked photo, already square-cropped and JPEG-encoded; uploaded on Save.
    @State private var pickedPhoto: (preview: UIImage, jpeg: Data)?
    @State private var isLoadingPhoto = false
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    @FocusState private var nameFocused: Bool

    init(
        userId: String,
        initialName: String,
        currentAvatarURL: URL?,
        initialUsername: String,
        initialPhone: String,
        initialPhoneVisible: Bool,
        initialEmailContact: String,
        initialEmailContactVisible: Bool,
        onSaved: @escaping (UpdateProfileRequest) -> Void
    ) {
        self.userId                     = userId
        self.initialName                = initialName
        self.currentAvatarURL           = currentAvatarURL
        self.initialUsername            = initialUsername
        self.initialPhone               = initialPhone
        self.initialPhoneVisible        = initialPhoneVisible
        self.initialEmailContact        = initialEmailContact
        self.initialEmailContactVisible = initialEmailContactVisible
        self.onSaved                    = onSaved
        _name                = State(initialValue: initialName)
        _username            = State(initialValue: initialUsername)
        _phone               = State(initialValue: initialPhone)
        _phoneVisible        = State(initialValue: initialPhoneVisible)
        _emailContact        = State(initialValue: initialEmailContact)
        _emailContactVisible = State(initialValue: initialEmailContactVisible)
    }

    private var trimmedName: String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    private var nameIsValid: Bool { !trimmedName.isEmpty && trimmedName.count <= Self.nameMaxLength }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Background.base.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        photoSection

                        // Name — what every other rider sees on the map, in lobbies and summaries.
                        fieldSection(header: "NAME", note: nameNote) {
                            TextField("Your name", text: $name)
                                .dsText(.body)
                                .foregroundColor(DS.Text.primary.base)
                                .tint(DS.Accent.base)
                                .textContentType(.name)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                                .focused($nameFocused)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .onChange(of: name) { _, new in
                                    // Hard stop at the limit rather than an error after the fact.
                                    if new.count > Self.nameMaxLength { name = String(new.prefix(Self.nameMaxLength)) }
                                }
                        }

                        // Username
                        fieldSection(
                            header: "USERNAME",
                            note: "Optional. Shown under your name on your profile."
                        ) {
                            styledTextField("Choose a username", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        // Phone
                        fieldSection(header: "MOBILE NUMBER") {
                            styledTextField("e.g. +91 98765 43210", text: $phone)
                                .keyboardType(.phonePad)
                                .textContentType(.telephoneNumber)
                            visibilityRow(label: "Visible to other riders", isOn: $phoneVisible)
                        }

                        // Email contact
                        fieldSection(header: "CONTACT EMAIL") {
                            styledTextField("e.g. you@example.com", text: $emailContact)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .textInputAutocapitalization(.never)
                            visibilityRow(label: "Visible to other riders", isOn: $emailContactVisible)
                        }

                        if let err = errorMessage {
                            DSInlineError(message: LocalizedStringKey(err))
                        }

                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(DS.Text.secondary.base)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().tint(DS.Accent.base)
                    } else {
                        Button("Save") { Task { await save() } }
                            .foregroundColor(nameIsValid && !isLoadingPhoto ? DS.Accent.base : DS.Text.disabled.base)
                            .fontWeight(.semibold)
                            .disabled(!nameIsValid || isLoadingPhoto)
                    }
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await loadPhoto(item) }
            }
        }
    }

    /// Live hint under the name: the rule while it's empty, a countdown near the limit.
    private var nameNote: String {
        if trimmedName.isEmpty { return "Other riders need a name to see on the map." }
        let left = Self.nameMaxLength - trimmedName.count
        if left <= 10 { return left == 1 ? "1 character left" : "\(left) characters left" }
        return "Other riders see this name on the map, in lobbies and in ride summaries."
    }

    // MARK: - Photo

    private var photoSection: some View {
        VStack(spacing: DS.Space.p3) {
            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                ZStack {
                    if let preview = pickedPhoto?.preview {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFill()
                            .frame(width: DS.AvatarSize.xxl, height: DS.AvatarSize.xxl)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(DS.Accent.base, lineWidth: DS.BorderWidth.focus))
                    } else {
                        DSAvatar(
                            name: trimmedName.isEmpty ? initialName : trimmedName,
                            id: userId,
                            imageURL: currentAvatarURL,
                            size: DS.AvatarSize.xxl,
                            highlightRing: DS.Accent.base
                        )
                    }
                    if isLoadingPhoto {
                        Circle().fill(.black.opacity(0.45))
                            .frame(width: DS.AvatarSize.xxl, height: DS.AvatarSize.xxl)
                        ProgressView().tint(DS.Text.primary.base)
                    }
                }
                .overlay(alignment: .bottomTrailing) { AvatarEditBadge() }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change profile photo")
            .disabled(isSaving)

            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                Text(pickedPhoto == nil ? "Change Photo" : "Choose Another Photo")
                    .dsText(.bodyStrong)
                    .foregroundStyle(DS.Accent.base)
                    .frame(minHeight: DS.Target.minimum)
            }
            .disabled(isSaving)
            .accessibilityHidden(true)   // the avatar above is the same control, already labelled

            Text("Your photo is visible to riders in your convoys.")
                .dsText(.helper)
                .foregroundColor(DS.Text.secondary.base)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        isLoadingPhoto = true
        errorMessage = nil
        defer { isLoadingPhoto = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let prepared = Self.avatarJPEG(from: image) else {
            errorMessage = "That photo couldn't be read. Try a different one."
            return
        }
        pickedPhoto = prepared
    }

    /// Centre-crops to a square and scales to 512 px: avatars render as circles and never larger
    /// than ~100 pt, so anything bigger is upload time spent on pixels nobody sees.
    static func avatarJPEG(from image: UIImage, side: CGFloat = 512) -> (preview: UIImage, jpeg: Data)? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = side / min(size.width, size.height)
        let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: (side - drawSize.width) / 2, y: (side - drawSize.height) / 2,
                                  width: drawSize.width, height: drawSize.height))
        }
        guard let jpeg = rendered.jpegData(compressionQuality: 0.85) else { return nil }
        return (rendered, jpeg)
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func fieldSection<Content: View>(
        header: String,
        note: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedStringKey(header))
                .dsText(.sectionLabel)
                .foregroundColor(DS.Accent.base)
            VStack(spacing: 0) { content() }
                .background(DS.Surface.raised)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.Border.strongColor.opacity(0.4), lineWidth: 1))
            if let note {
                Text(LocalizedStringKey(note))
                    .dsText(.helper)
                    .foregroundColor(DS.Text.secondary.base)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func styledTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .dsText(.body)
            .foregroundColor(DS.Text.primary.base)
            .tint(DS.Accent.base)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
    }

    private func visibilityRow(label: String, isOn: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(DS.Border.strongColor.opacity(0.4))
                .frame(height: 0.5)
                .padding(.horizontal, 16)
            Toggle(isOn: isOn) {
                Text(LocalizedStringKey(label))
                    .dsText(.body)
                    .foregroundColor(DS.Text.secondary.base)
            }
            .tint(DS.Accent.base)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Save

    /// Photo, then name, then the rest. Each step is idempotent, so if one fails the rider can
    /// just tap Save again; nothing already saved is lost or duplicated.
    private func save() async {
        guard nameIsValid else { nameFocused = true; return }
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        let req = UpdateProfileRequest(
            username:            username.trimmingCharacters(in: .whitespaces).isEmpty ? nil : username.trimmingCharacters(in: .whitespaces),
            phone:               phone.trimmingCharacters(in: .whitespaces).isEmpty ? nil : phone.trimmingCharacters(in: .whitespaces),
            phoneVisible:        phoneVisible,
            emailContact:        emailContact.trimmingCharacters(in: .whitespaces).isEmpty ? nil : emailContact.trimmingCharacters(in: .whitespaces),
            emailContactVisible: emailContactVisible
        )
        do {
            var identityChanged = false
            if let photo = pickedPhoto {
                _ = try await APIClient.shared.uploadProfilePhoto(jpeg: photo.jpeg)
                pickedPhoto = nil
                photoItem = nil
                identityChanged = true
            }
            if trimmedName != initialName {
                _ = try await APIClient.shared.updateName(trimmedName)
                identityChanged = true
            }
            try await APIClient.shared.updateProfile(req)
            // The server wrote Clerk; pull it so the header (and the launch sync) see the edit now.
            if identityChanged { _ = try? await clerk.user?.reload() }
            onSaved(req)
            dismiss()
        } catch {
            // USERNAME_TAKEN used to be special-cased here; it now has wording in the central map
            // like every other code, so this one branch covers all of them.
            errorMessage = error.riderMessage
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(AppState())
        .environmentObject(RideRealtimeSession())
        .environmentObject(MembershipStore())
        .environmentObject(PaywallPresenter())
}
