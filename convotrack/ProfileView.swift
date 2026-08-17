import SwiftUI
import ClerkKit

struct ProfileView: View {
    @Binding var activeTab: ConvoTrackBottomNav.Tab
    @Environment(Clerk.self) private var clerk
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: MembershipStore
    @Environment(\.dismiss) private var dismiss
    @State private var userProfile: UserMeResponse? = nil
    @State private var notifyNearbyRides: Bool = true
    @State private var isSigningOut = false
    @State private var showMembership = false
    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String?
    @State private var showDeleteError = false
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

    var body: some View {
        ZStack(alignment: .top) {
            Color.surfaceDim.ignoresSafeArea()

            Color.clear
                .background(
                    RadialGradient(
                        gradient: Gradient(colors: [Color.primaryFixed.opacity(0.08), .clear]),
                        center: .top,
                        startRadius: 0,
                        endRadius: 300
                    )
                )
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    Color.clear.frame(height: 72)

                    // Membership Card
                    membershipCard
                        .padding(.horizontal, 20)

                    // Preferences
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PREFERENCES")
                            .font(.labelCaps)
                            .foregroundColor(Color.primaryFixed)
                            .tracking(4)
                            .padding(.horizontal, 4)

                        HStack {
                            Label("Notify nearby rides", systemImage: "bell.badge")
                                .font(.bodyMd)
                                .foregroundColor(Color.onSurface)
                            Spacer()
                            Toggle("", isOn: $notifyNearbyRides)
                                .labelsHidden()
                                .tint(Color.primaryFixed)
                                .onChange(of: notifyNearbyRides) { _, newVal in
                                    Task { try? await APIClient.shared.updateProfile(
                                        UpdateProfileRequest(notifyNearbyRides: newVal)) }
                                }
                        }
                        .padding(16)
                        .background(Color.surfaceContainerHigh.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outlineVariant.opacity(0.4), lineWidth: 1))
                    }
                    .padding(.horizontal, 20)

                    // Logout
                    Button(action: {
                        Task {
                            isSigningOut = true
                            appState.currentRideId = nil
                            appState.inviteCode = nil
                            appState.currentRide = nil
                            try? await Clerk.shared.auth.signOut()
                            dismiss()
                        }
                    }) {
                        HStack(spacing: 8) {
                            if isSigningOut {
                                ProgressView().tint(Color.errorColor).scaleEffect(0.8)
                            } else {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                            }
                            Text(isSigningOut ? "SIGNING OUT..." : "LOGOUT").font(.bodyLg)
                        }
                        .foregroundColor(Color.errorColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.surfaceContainerHigh)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.errorColor.opacity(0.3), lineWidth: 1))
                    }
                    .disabled(isSigningOut)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    // Delete Account — required by App Store Guideline 5.1.1
                    Button(action: { showDeleteAccountConfirm = true }) {
                        HStack(spacing: 8) {
                            if isDeletingAccount {
                                ProgressView().tint(Color.errorColor).scaleEffect(0.8)
                            } else {
                                Image(systemName: "person.crop.circle.badge.minus")
                            }
                            Text(isDeletingAccount ? "DELETING..." : "DELETE ACCOUNT").font(.bodyMd)
                        }
                        .foregroundColor(Color.errorColor.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.errorContainer.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.errorColor.opacity(0.2), lineWidth: 1))
                    }
                    .disabled(isDeletingAccount || isSigningOut)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                    Color.clear.frame(height: 120)
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .task {
                if let p = try? await APIClient.shared.fetchMe() {
                    userProfile = p
                    notifyNearbyRides = p.notifyNearbyRides
                }
            }
            .sheet(isPresented: $showMembership) {
                MembershipView().environmentObject(store)
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
                            if let p = try? await APIClient.shared.fetchMe() {
                                userProfile = p
                                notifyNearbyRides = p.notifyNearbyRides
                            }
                        }
                    }
                )
            }
            .confirmationDialog(
                "Delete Account",
                isPresented: $showDeleteAccountConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete your account and all ride history. Active subscriptions must be cancelled separately in Settings > Apple ID > Subscriptions. This cannot be undone.")
            }
            .alert("Deletion Failed", isPresented: $showDeleteError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "An error occurred. Please try again.")
            }

            // Floating top bar
            HStack(alignment: .center, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: avatarUrl) { img in
                        img.resizable().scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.primaryFixed, lineWidth: 2))
                    } placeholder: {
                        Circle()
                            .fill(Color.surfaceVariant)
                            .frame(width: 40, height: 40)
                            .overlay(Circle().stroke(Color.primaryFixed, lineWidth: 2))
                            .overlay(
                                Text(String(displayName.prefix(1)).uppercased())
                                    .font(.bodyMd).foregroundColor(Color.primaryFixed)
                            )
                    }
                    ZStack {
                        Circle().fill(Color.primaryFixed).frame(width: 11, height: 11)
                        Circle().fill(Color.onPrimaryContainer).frame(width: 5, height: 5)
                    }
                }

                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.headlineMd)
                        .foregroundColor(Color.onSurface)
                        .lineLimit(1)
                    Button(action: { showEditProfile = true }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.onSurfaceVariant)
                            .frame(width: 28, height: 28)
                            .background(Color.surfaceContainerHigh)
                            .clipShape(Circle())
                    }
                }

                Spacer()
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.iconNav)
                    .foregroundColor(Color.primaryFixed)
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 56)
        }
    }
}

// MARK: - Account Actions

extension ProfileView {
    func deleteAccount() async {
        isDeletingAccount = true
        do {
            try await clerk.user?.delete()
            appState.currentRideId = nil
            appState.inviteCode = nil
            appState.currentRide = nil
            dismiss()
        } catch {
            deleteError = error.localizedDescription
            showDeleteError = true
            isDeletingAccount = false
        }
    }
}

// MARK: - Membership Card

extension ProfileView {
    @ViewBuilder
    var membershipCard: some View {
        if store.isPremium {
            premiumStatusCard
        } else {
            upgradeCard
        }
    }

    private var upgradeCard: some View {
        Button { showMembership = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.primaryFixed.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "crown.fill")
                        .font(.iconMd)
                        .foregroundColor(Color.primaryFixed)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("CONVOTRACK PRO")
                        .font(.labelCaps)
                        .foregroundColor(Color.primaryFixed)
                        .tracking(2)
                    Text("Bigger packs · Unlimited rides")
                        .font(.captionMd)
                        .foregroundColor(Color.onSurfaceVariant)
                }

                Spacer()

                Text("UPGRADE")
                    .font(.labelCaps)
                    .foregroundColor(Color.onPrimaryFixed)
                    .tracking(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.primaryFixed)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(16)
            .background(Color.primaryFixed.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primaryFixed.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var premiumStatusCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.tertiaryFixed.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "crown.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color.tertiaryFixed)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("PRO MEMBER")
                        .font(.labelCaps)
                        .foregroundColor(Color.tertiaryFixed)
                        .tracking(2)
                }
                if let endsAt = store.premiumEndsAt {
                    Text("Renews \(endsAt.formatted(.dateTime.month(.abbreviated).day().year()))")
                        .font(.captionMd)
                        .foregroundColor(Color.onSurfaceVariant)
                }
            }

            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.iconLg)
                .foregroundColor(Color.tertiaryFixed)
        }
        .padding(16)
        .background(Color.tertiaryFixed.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.tertiaryFixed.opacity(0.25), lineWidth: 1))
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
                Color.surfaceDim.ignoresSafeArea()

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
                                .font(.bodyMd)
                                .foregroundColor(Color.errorColor)
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
                        .foregroundColor(Color.onSurfaceVariant)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().tint(Color.primaryFixed)
                    } else {
                        Button("Save") { Task { await save() } }
                            .foregroundColor(Color.primaryFixed)
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
                .font(.labelCaps)
                .foregroundColor(Color.primaryFixed)
                .tracking(3)
            VStack(spacing: 0) { content() }
                .background(Color.surfaceContainerHigh)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outlineVariant.opacity(0.4), lineWidth: 1))
            if let note {
                Text(note)
                    .font(.captionMd)
                    .foregroundColor(Color.onSurfaceVariant)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func styledTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.bodyMd)
            .foregroundColor(Color.onSurface)
            .tint(Color.primaryFixed)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
    }

    private func visibilityRow(label: String, isOn: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.outlineVariant.opacity(0.4))
                .frame(height: 0.5)
                .padding(.horizontal, 16)
            HStack {
                Text(label)
                    .font(.bodyMd)
                    .foregroundColor(Color.onSurfaceVariant)
                Spacer()
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .tint(Color.primaryFixed)
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
        } catch APIClientError.serverError(let msg) where msg == "USERNAME_TAKEN" {
            errorMessage = "That username is already taken. Please choose another."
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

#Preview {
    ProfileView(activeTab: .constant(.profile))
        .environmentObject(AppState())
}
