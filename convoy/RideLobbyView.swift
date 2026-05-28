import SwiftUI

struct RideLobbyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false
    @State private var showQRModal = false
    @State private var startPressed = false
    @State private var showRiderDetail = false

    private let riders: [(name: String, bike: String, status: String, imgUrl: String)] = [
        ("Alex", "KTM ADVENTURE 390", "READY", "https://lh3.googleusercontent.com/aida-public/AB6AXuBQNuWhOtF3DXKKQ0DmErPqLF0oWDEa_-eO_fw2AexTNja0nmY07Crqv4TCZJawBTn6os3ACLTv3mZTFhDslWlfmm2OF0AgcFr-KOQhPjchRckoWnqjcsVN2-m3S21KpfeytbD7v63RnTqD3SO3RU9s3t3mlBVanN5ZatrrH4QuHdipl3aKe01_73ao6RBFd8A49aHQzsR__L8HmO1wfsZUemj_waCy5WqREtcvUG0Q6ZLjKUGliBZrcE28kioiP8cgYeAipweSYSg"),
        ("Sam", "DUCATI MULTISTRADA", "READY", "https://lh3.googleusercontent.com/aida-public/AB6AXuC0FnjMnOzopKSx-C6lRFSxZB2IDrZQfCAB7FkhPazac9ff8lLnRu_YfTbe5Uh9efwQ-LAuzMBi36kfb6tMjbCkObZgTPHzutgzCb4M1EI1u7sU7Dp4nWFQ_GKZuU0xKTnsK2QsQ8BNxqDx37boXDA04tWO1xgsvrV2v7EWL8rtwialXEjze2pI-vtQvi-VKlIgMoMW7KSVcNFGqHbnvU2iDfPdQxXdCr93DDPaHfK6cKZ_eFfbJs5hxL-6A5mFdkZ-JdwFrNMGQjU"),
        ("Rahul", "BMW R1250 GS", "WAITING", "https://lh3.googleusercontent.com/aida-public/AB6AXuDmmB6IbIMz2C0QhSGsvfXl8savmkcfxNSmLZI6rgxq7PlCnBGef1D6-S5QJtzfePXR70mpXdxDchrfvxQFaqk8iLFh9QsdXA4AlbYdlSIkEVxfQinHlQ4pM_W3jo2UbXqjIGv575AdAwq5iLd8E60x-PKS-WuJ1sYx9tMCv_4kwlhAR-nlKIECtDYhdZXnSiBTuTwS53qExqViWRZ6Fbm9SrtAEPGpyGWIXZl4GqGzb21KQl__8ID34SnzCZWLhBb5VrUvidAJRT8")
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.surfaceDim.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Map Route Preview
                    ZStack(alignment: .bottom) {
                        AsyncImage(url: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuC6afDKDHLRQh89eKq9acEWfISyVapMQBJCIwQgAcyfyAi7y3-_tWHf2gv_gMsx7k3SypBiqAHMLSeu_nnxMsy5EXsyqYjLs0ZEmuIIl1hLAvpMEUu3bjUHobDLIDAmfnNz2v4bQPHsnoIoaTvd1nftmIFq0VsSftT_dfSUlDPNlGPPJ_MDHuRut6D9Cvl92mWShq8a6hgHU-lq0w4QbsMLbew4Usha0_x3LXHB0TmKmNoverYNfDnVQnVdfh5KPQgCY5jQ9uAVTlk")) { image in
                            image.resizable().scaledToFill()
                                .grayscale(0.4).opacity(0.6)
                        } placeholder: {
                            Color.surfaceContainerLow
                        }
                        .frame(maxWidth: .infinity, minHeight: 360)
                        .clipped()

                        LinearGradient(
                            colors: [Color.surfaceDim, Color.surfaceDim.opacity(0.4), .clear],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                        .frame(height: 360)

                        // Stat pills
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                FloatingStatPill(label: "DISTANCE", value: "182", unit: "km")
                                FloatingStatPill(label: "RIDERS", value: "8", unit: nil)
                                FloatingStatPill(label: "STATUS", value: "Waiting", unit: nil, dotColor: Color.secondaryFixed)
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                        }
                    }
                    .frame(height: 360)

                    // Squad Roster
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("SQUAD ROSTER")
                                .font(.labelCaps)
                                .foregroundColor(Color.primaryFixed)
                                .tracking(4)
                            Spacer()
                            HStack(spacing: 8) {
                                ShareButton(icon: "link") { showShareSheet = true }
                                ShareButton(icon: "qrcode") { showQRModal = true }
                            }
                        }

                        VStack(spacing: 12) {
                            ForEach(riders, id: \.name) { rider in
                                Button(action: { showRiderDetail = true }) {
                                    LobbyRiderRow(rider: rider)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(20)

                    Color.clear.frame(height: 120)
                }
            }

            // Fixed Start Button
            VStack(spacing: 0) {
                LinearGradient(colors: [Color.surfaceDim.opacity(0), Color.surfaceDim], startPoint: .top, endPoint: .bottom)
                    .frame(height: 40)

                Button(action: { startPressed.toggle() }) {
                    HStack(spacing: 12) {
                        Image(systemName: startPressed ? "checkmark" : "play.fill")
                            .font(.system(size: 20, weight: .bold))
                        Text(startPressed ? "ALL SYSTEMS GO" : "START RIDE")
                            .font(.headlineMd)
                            .tracking(-0.5)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(startPressed ? Color.tertiaryFixed : Color.primaryFixed)
                    .foregroundColor(startPressed ? Color.onTertiaryContainer : Color.onPrimaryFixed)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: Color.primaryFixed.opacity(0.3), radius: 20)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 96)
                .background(Color.surfaceDim)
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle("Coorg Morning Ride")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "arrow.left").foregroundColor(Color.primaryFixed)
                }
            }
        }
        .sheet(isPresented: $showRiderDetail) {
            RiderDetailDrawer()
        }
        .sheet(isPresented: $showQRModal) {
            QRCodeModal()
        }
        .preferredColorScheme(.dark)
    }
}

struct FloatingStatPill: View {
    let label: String
    let value: String
    let unit: String?
    var dotColor: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.labelCaps).foregroundColor(Color.onSurfaceVariant)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let dotColor {
                    Circle().fill(dotColor).frame(width: 7, height: 7).offset(y: -1)
                }
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(dotColor ?? Color.onSurface)
                if let unit {
                    Text(unit)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.onSurfaceVariant)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surfaceContainerHigh.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.outline.opacity(0.2), lineWidth: 1))
    }
}

struct ShareButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(Color.onSurface)
                .frame(width: 44, height: 44)
                .background(Color.surfaceContainerHigh.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outline.opacity(0.2), lineWidth: 1))
        }
    }
}

struct LobbyRiderRow: View {
    let rider: (name: String, bike: String, status: String, imgUrl: String)

    var body: some View {
        HStack(spacing: 16) {
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: URL(string: rider.imgUrl)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(Color.surfaceVariant)
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                .opacity(rider.status == "READY" ? 1 : 0.5)

                Circle()
                    .fill(rider.status == "READY" ? Color.primaryFixed : Color.surfaceVariant)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.surfaceDim, lineWidth: 2))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(rider.name).font(.bodyLg).foregroundColor(rider.status == "READY" ? Color.onSurface : Color.onSurface.opacity(0.7))
                Text(rider.bike).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(Color.onSurfaceVariant).tracking(1)
            }

            Spacer()

            Text(rider.status)
                .font(.labelCaps)
                .foregroundColor(rider.status == "READY" ? Color.onPrimaryContainer : Color.onSurfaceVariant)
                .tracking(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(rider.status == "READY" ? Color.primaryContainer : Color.surfaceVariant)
                .clipShape(Capsule())
        }
        .padding(16)
        .background(Color.surfaceContainerHigh.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(rider.status == "READY" ? Color.primaryFixed : Color.outline, lineWidth: 1),
            alignment: .leading
        )
        .overlay(
            HStack {
                Rectangle()
                    .fill(rider.status == "READY" ? Color.primaryFixed : Color.outline)
                    .frame(width: 4)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                Spacer()
            }
        )
    }
}

struct QRCodeModal: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.surfaceDim.opacity(0.95).ignoresSafeArea()

            VStack(spacing: 32) {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark").font(.system(size: 20)).foregroundColor(Color.onSurfaceVariant)
                            .frame(width: 44, height: 44)
                    }
                }

                Text("JOIN CONVOY")
                    .font(.headlineMd)
                    .foregroundColor(Color.primaryFixed)
                    .tracking(2)

                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .frame(width: 256, height: 256)
                    .overlay(
                        Image(systemName: "qrcode")
                            .font(.system(size: 200))
                            .foregroundColor(Color.surfaceContainerLowest)
                    )

                Text("Scan to join the Coorg Morning Ride")
                    .font(.bodyMd)
                    .foregroundColor(Color.onSurfaceVariant)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .padding(24)
            .padding(.top, 16)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    RideLobbyView()
}
