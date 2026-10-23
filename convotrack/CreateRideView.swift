import SwiftUI
import CoreLocation

// MARK: - Create Ride View

/// New ride, planned on the map (`RidePlannerView`). This screen owns the plan's lifetime and
/// the create call; the planner owns everything on screen.
struct CreateRideView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var membershipStore: MembershipStore
    @EnvironmentObject private var paywall: PaywallPresenter
    @Environment(\.dismiss) private var dismiss

    @StateObject private var planner = RidePlannerModel()

    private var riderCap: Int { membershipStore.riderCap }

    // API state
    @State private var isCreating = false
    @State private var errorMessage: String?
    /// The last create was refused for a plan reason (trial over / monthly rides used up).
    @State private var createBlockedByPlan = false
    @State private var showError = false

    var body: some View {
        RidePlannerView(
            model: planner,
            riderCap: riderCap,
            isPremium: membershipStore.isPremium,
            onUpgrade: { paywall.present(.riderCap) },
            onClose: { dismiss() }
        ) {
            DSPrimaryButton(title: "Create ride", systemImage: "arrow.turn.up.right", isLoading: isCreating) {
                Task { await createRide() }
            }
            .disabled(!planner.canCommit(isBusy: isCreating))
        }
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        .alert("Failed to Create Ride", isPresented: $showError) {
            if createBlockedByPlan {
                Button("Go Pro") { paywall.present(.createBlocked) }
                Button("Not now", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .onAppear {
            // First ride only: start from the group size the rider told us during onboarding.
            if let suggested = OnboardingState.consumeSuggestedMaxRiders() {
                planner.maxRiders = max(2, suggested)
            }
            // Clamp to plan limit in case default exceeds it (e.g. free tier = 5)
            planner.maxRiders = min(planner.maxRiders, riderCap)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Create Ride

    @MainActor
    private func createRide() async {
        isCreating = true
        defer { isCreating = false }
        guard let waypoints = await planner.resolvedWaypoints(), let dest = waypoints.last else { return }

        let body = CreateRideRequest(
            title: planner.title.trimmingCharacters(in: .whitespaces),
            destinationName: dest.name,
            destinationLat: dest.lat,
            destinationLng: dest.lng,
            distanceMeters: planner.distanceMeters,
            estimatedDurationSeconds: Int(planner.durationSeconds),
            maxAllowedParticipants: planner.maxRiders,
            routePolyline: GoogleDirectionsService.encodePolyline(planner.routeCoordinates),
            waypoints: waypoints
        )

        do {
            let response = try await APIClient.shared.createRide(body)
            // Seed the full ride BEFORE flipping `currentRideId` — that assignment is what
            // pushes the lobby, and the lobby, the home Active Ride card and the navigation
            // screen all read `currentRide` on their first frame. Leaving it nil there is what
            // left the hero photo blank (`destinationPhotoKey` stays empty, so the hero parks in
            // `.resolving` forever), demoted the leader to a MARK AS READY button, and sent
            // `ActiveRideSection` off on a duplicate concurrent fetch of its own.
            //
            // A failed fetch assigns nil, which is exactly the old behaviour — no stale ride can
            // survive here — and the lobby's own retrying fetch then fills it in.
            appState.currentRide = try? await APIClient.shared.getRide(response.rideId)
            appState.inviteCode = response.inviteCode
            appState.currentRideId = response.rideId
        } catch {
            Analytics.capture(.createRideFailed, ["plan_limit": error.isPlanLimit])
            errorMessage = error.riderMessage
            createBlockedByPlan = error.isPlanLimit
            showError = true
        }
    }
}

#Preview {
    CreateRideView()
        .environmentObject(AppState())
        .environmentObject(RideRealtimeSession())
        .environmentObject(MembershipStore())
        .environmentObject(PaywallPresenter())
}
