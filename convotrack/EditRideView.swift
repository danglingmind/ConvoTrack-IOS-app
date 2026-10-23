import SwiftUI
import CoreLocation
import ClerkKit

/// A saved ride, re-planned on the map (`RidePlannerView` in edit mode). This screen owns the
/// save and delete calls; the planner owns everything on screen.
struct EditRideView: View {
    @EnvironmentObject private var membershipStore: MembershipStore
    @EnvironmentObject private var paywall: PaywallPresenter
    @Environment(Clerk.self) private var clerk
    @Environment(\.dismiss) private var dismiss

    let ride: Ride

    /// Called after the ride is successfully deleted, so the presenting lobby can tear
    /// down its session and pop back instead of refreshing a now-nonexistent ride.
    var onDeleted: () -> Void = {}

    @StateObject private var planner: RidePlannerModel

    private var riderCap: Int { membershipStore.riderCap }

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showDiscardConfirm = false

    @State private var isDeleting = false
    @State private var showDeleteConfirm = false
    @State private var deleteErrorMessage: String?
    @State private var showDeleteError = false

    /// Only the ride's creator (leader) may delete it. Read reactively from Clerk so a
    /// still-loading identity resolves the moment it lands.
    private var isLeader: Bool {
        guard let uid = clerk.user?.id, !uid.isEmpty else { return false }
        return uid == ride.leaderId
    }

    init(ride: Ride, onDeleted: @escaping () -> Void = {}) {
        self.ride = ride
        self.onDeleted = onDeleted
        _planner = StateObject(wrappedValue: RidePlannerModel(ride: ride))
    }

    private var canSave: Bool {
        planner.hasChanges && planner.canCommit(isBusy: isSaving || isDeleting)
    }

    var body: some View {
        RidePlannerView(
            model: planner,
            riderCap: riderCap,
            isPremium: membershipStore.isPremium,
            mode: .edit,
            onUpgrade: { paywall.present(.riderCap) },
            onClose: close,
            onDelete: isLeader ? { showDeleteConfirm = true } : nil
        ) {
            DSPrimaryButton(title: "Save changes", systemImage: "checkmark", isLoading: isSaving) {
                Task { await saveRide() }
            }
            .disabled(!canSave)
        }
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        // An edge swipe would drop unsaved changes without asking; Back asks first.
        .swipeBackDisabled(planner.hasChanges)
        .confirmationDialog("Discard your changes?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("The ride stays as it was saved.")
        }
        .alert("Failed to Save Ride", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .alert("Delete This Ride?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Ride", role: .destructive) { Task { await deleteRide() } }
        } message: {
            Text("This permanently deletes the ride for everyone. This can't be undone.")
        }
        .alert("Failed to Delete Ride", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "An unknown error occurred.")
        }
        .task {
            // Show the saved route at once, then load the alternatives and keep the leader's
            // earlier pick selected.
            planner.fitCameraToRoute(animated: false)
            planner.recalculateRoute(preferStoredMatch: true)
        }
        .preferredColorScheme(.dark)
    }

    private func close() {
        if planner.hasChanges {
            showDiscardConfirm = true
        } else {
            dismiss()
        }
    }

    // MARK: - Delete

    @MainActor
    private func deleteRide() async {
        guard isLeader else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await APIClient.shared.deleteRide(ride.id)
            await ImageCache.shared.purge(tag: ride.id)   // its map snapshot and share card
            RideThumbnail.forgetDestination(rideId: ride.id)
            onDeleted()
            dismiss()
        } catch {
            deleteErrorMessage = error.riderMessage
            showDeleteError = true
        }
    }

    // MARK: - Save

    @MainActor
    private func saveRide() async {
        isSaving = true
        defer { isSaving = false }
        guard let waypoints = await planner.resolvedWaypoints(), let dest = waypoints.last else { return }

        let request = UpdateRideRequest(
            title:                    planner.title.trimmingCharacters(in: .whitespaces),
            destinationName:          dest.name,
            destinationLat:           dest.lat,
            destinationLng:           dest.lng,
            distanceMeters:           planner.distanceMeters,
            estimatedDurationSeconds: Int(planner.durationSeconds),
            maxAllowedParticipants:   planner.maxRiders,
            routePolyline:            GoogleDirectionsService.encodePolyline(planner.routeCoordinates),
            waypoints:                waypoints
        )

        do {
            try await APIClient.shared.updateRide(ride.id, request)
            // New route/destination: drop the ride's cached map and card, and the remembered
            // destination so history thumbnails re-resolve the photo for the new place.
            await ImageCache.shared.purge(tag: ride.id)
            RideThumbnail.forgetDestination(rideId: ride.id)
            dismiss()
        } catch {
            errorMessage = error.riderMessage
            showError = true
        }
    }
}
