import SwiftUI
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

    private var displayName: String {
        if let username = userProfile?.username, !username.isEmpty { return username }
        let parts = [clerk.user?.firstName, clerk.user?.lastName]
            .compactMap { $0 }.filter { !$0.isEmpty }
        let name = parts.joined(separator: " ")
        return name.isEmpty ? (clerk.user?.username ?? "Rider") : name
    }

    private var avatarUrl: URL? {
        guard let str = clerk.user?.imageUrl, !str.isEmpty else { return nil }
        return URL(string: str)
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

                    DSSettingsGroup {
                        DSSettingsRow(systemImage: "bell", title: "Notifications", trailing: .externalLink) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        DSSettingsRow(systemImage: "creditcard", title: "Membership & Billing") { paywall.present(.profile) }
                        DSSettingsRow(systemImage: "hand.raised", title: "Privacy Policy", trailing: .externalLink) {
                            if let url = URL(string: AppURLs.privacyPolicy) { openURL(url) }
                        }
                        DSSettingsRow(systemImage: "doc.text", title: "Terms of Service", trailing: .externalLink, showsDivider: false) {
                            if let url = URL(string: AppURLs.termsOfService) { openURL(url) }
                        }
                    }

                    VStack(spacing: DS.Space.p3) {
                        DSSettingsGroup {
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
        .sheet(isPresented: $showEditProfile) {
            EditProfileSheet(
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
            DSAvatar(
                name: displayName,
                id: clerk.user?.id ?? displayName,
                imageURL: avatarUrl,
                size: DS.AvatarSize.xxl,
                highlightRing: DS.Accent.base
            )
            HStack(spacing: DS.Space.p2) {
                Text(displayName)
                    .dsText(.titleLarge)
                    .foregroundStyle(DS.Text.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                DSSquareIconButton(systemImage: "pencil", label: "Edit profile") { showEditProfile = true }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Three equal columns; one per row at accessibility sizes.
    private var stats: some View {
        DSAdaptiveStack(spacing: DS.Space.p3, verticalAlignment: .top) {
            DSStatTile(systemImage: "flag", label: "Rides", value: rideCount, fillsWidth: true, showsIcon: false)
            DSStatTile(systemImage: "point.topleft.down.to.point.bottomright.curvepath", label: "Total km", value: totalKm, fillsWidth: true, showsIcon: false)
            DSStatTile(systemImage: "person.fill", label: "Rides led", value: ridesLed, fillsWidth: true, showsIcon: false)
        }
    }

    private func signOut() {
        Task {
            isSigningOut = true
            appState.currentRideId = nil
            appState.inviteCode = nil
            appState.currentRide = nil
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

struct EditProfileSheet: View {
    let initialUsername: String
    let initialPhone: String
    let initialPhoneVisible: Bool
    let initialEmailContact: String
    let initialEmailContactVisible: Bool
    let onSaved: (UpdateProfileRequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var username: String
    @State private var phone: String
    @State private var phoneVisible: Bool
    @State private var emailContact: String
    @State private var emailContactVisible: Bool
    @State private var isSaving = false
    @State private var errorMessage: String? = nil

    init(
        initialUsername: String,
        initialPhone: String,
        initialPhoneVisible: Bool,
        initialEmailContact: String,
        initialEmailContactVisible: Bool,
        onSaved: @escaping (UpdateProfileRequest) -> Void
    ) {
        self.initialUsername            = initialUsername
        self.initialPhone               = initialPhone
        self.initialPhoneVisible        = initialPhoneVisible
        self.initialEmailContact        = initialEmailContact
        self.initialEmailContactVisible = initialEmailContactVisible
        self.onSaved                    = onSaved
        _username            = State(initialValue: initialUsername)
        _phone               = State(initialValue: initialPhone)
        _phoneVisible        = State(initialValue: initialPhoneVisible)
        _emailContact        = State(initialValue: initialEmailContact)
        _emailContactVisible = State(initialValue: initialEmailContactVisible)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Background.base.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Username
                        fieldSection(
                            header: "USERNAME",
                            note: "Other riders see your username instead of your name"
                        ) {
                            styledTextField("Choose a username", text: $username)
                        }

                        // Phone
                        fieldSection(header: "MOBILE NUMBER") {
                            styledTextField("e.g. +91 98765 43210", text: $phone)
                                .keyboardType(.phonePad)
                            visibilityRow(label: "Visible to other riders", isOn: $phoneVisible)
                        }

                        // Email contact
                        fieldSection(header: "CONTACT EMAIL") {
                            styledTextField("e.g. you@example.com", text: $emailContact)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                            visibilityRow(label: "Visible to other riders", isOn: $emailContactVisible)
                        }

                        if let err = errorMessage {
                            Text(err)
                                .dsText(.body)
                                .foregroundColor(DS.Status.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }

                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
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
                            .foregroundColor(DS.Accent.base)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func fieldSection<Content: View>(
        header: String,
        note: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(header)
                .dsText(.sectionLabel)
                .foregroundColor(DS.Accent.base)
            VStack(spacing: 0) { content() }
                .background(DS.Surface.raised)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.Border.strongColor.opacity(0.4), lineWidth: 1))
            if let note {
                Text(note)
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
            HStack {
                Text(label)
                    .dsText(.body)
                    .foregroundColor(DS.Text.secondary.base)
                Spacer()
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .tint(DS.Accent.base)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Save

    private func save() async {
        errorMessage = nil
        isSaving = true
        let req = UpdateProfileRequest(
            username:            username.trimmingCharacters(in: .whitespaces).isEmpty ? nil : username.trimmingCharacters(in: .whitespaces),
            phone:               phone.trimmingCharacters(in: .whitespaces).isEmpty ? nil : phone.trimmingCharacters(in: .whitespaces),
            phoneVisible:        phoneVisible,
            emailContact:        emailContact.trimmingCharacters(in: .whitespaces).isEmpty ? nil : emailContact.trimmingCharacters(in: .whitespaces),
            emailContactVisible: emailContactVisible
        )
        do {
            try await APIClient.shared.updateProfile(req)
            onSaved(req)
            dismiss()
        } catch {
            // USERNAME_TAKEN used to be special-cased here; it now has wording in the central map
            // like every other code, so this one branch covers all of them.
            errorMessage = error.riderMessage
        }
        isSaving = false
    }
}

#Preview {
    ProfileView()
        .environmentObject(AppState())
        .environmentObject(RideRealtimeSession())
        .environmentObject(MembershipStore())
        .environmentObject(PaywallPresenter())
}
