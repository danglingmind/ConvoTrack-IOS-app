import SwiftUI

struct JoinRideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var inviteCode = ""
    @State private var showToast = false
    @State private var showScannerPlaceholder = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surfaceDim.ignoresSafeArea()
                    .overlay(
                        // Asphalt dot texture
                        Canvas { ctx, size in
                            for x in stride(from: 0, to: size.width, by: 24) {
                                for y in stride(from: 0, to: size.height, by: 24) {
                                    let rect = CGRect(x: x, y: y, width: 1.5, height: 1.5)
                                    ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.05)))
                                }
                            }
                        }
                    )

                ScrollView {
                    VStack(spacing: 32) {
                        // Hero HUD section
                        ZStack(alignment: .bottomLeading) {
                            AsyncImage(url: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuC5cr7RP__6cnlzy_FXSEwHuecBdhk1z8CjevrsLSh8580yPlvkaGAOgKvltHeI3SpSDe6BhCU-Wh0qivmOF65xwbO6Ok0rUgGwk3aJa3DBENGrwCrvoYok04hFxnERzE-xfJ2Cdd-w8UKnM51pdZnvnL7NmnzuWqZ_g5FXV-M4B0YoY5pLaeyM_S1Oexr5oUi51eUzZtsMsdzrnpdw-AcAfGEvftwpZ73YRHSxFdIQMRDU9tEkk2583rH7GxfwZ2X56DbQuZs9EjA")) { image in
                                image.resizable().scaledToFill()
                                    .opacity(0.4)
                            } placeholder: {
                                Color.surfaceContainerLow
                            }
                            .frame(maxWidth: .infinity, minHeight: 180)
                            .clipped()
                            .overlay(LinearGradient(colors: [.clear, Color.surfaceDim], startPoint: .top, endPoint: .bottom))

                            VStack(alignment: .leading, spacing: 4) {
                                Text("SYSTEM: STANDBY")
                                    .font(.labelCaps)
                                    .foregroundColor(Color.primaryFixed)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.surfaceContainerHighest)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .tracking(2)
                                Text("Ready to Connect")
                                    .font(.headlineMd)
                                    .foregroundColor(Color.onSurface)
                            }
                            .padding(16)
                        }
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))

                        // Invite Code Input
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 8) {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color.primaryFixed)
                                Text("ENTER INVITE CODE")
                                    .font(.labelCaps)
                                    .foregroundColor(Color.onSurfaceVariant)
                                    .tracking(4)
                            }

                            ZStack(alignment: .trailing) {
                                TextField("A1B2C3", text: $inviteCode)
                                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color.primaryFixed)
                                    .multilineTextAlignment(.center)
                                    .textCase(.uppercase)
                                    .frame(height: 64)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.surfaceContainerHighest)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(inviteCode.count == 6 ? Color.primaryFixed : Color.outlineVariant, lineWidth: 2)
                                    )
                                    .onChange(of: inviteCode) { _, newValue in
                                        if newValue.count == 6 {
                                            showToast = true
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                                                showToast = false
                                            }
                                        }
                                    }

                                Image(systemName: inviteCode.count == 6 ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(inviteCode.count == 6 ? Color.primaryFixed : Color.outlineVariant)
                                    .padding(.trailing, 16)
                            }

                            Text("Case-sensitive code provided by your Squad Leader.")
                                .font(.bodyMd)
                                .foregroundColor(Color.onSurfaceVariant.opacity(0.7))
                        }

                        // Divider
                        HStack(spacing: 16) {
                            Rectangle().frame(height: 1).foregroundColor(Color.outlineVariant.opacity(0.3))
                            Text("OR").font(.labelCaps).foregroundColor(Color.outline).tracking(2)
                            Rectangle().frame(height: 1).foregroundColor(Color.outlineVariant.opacity(0.3))
                        }

                        // QR Scanner
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 8) {
                                Image(systemName: "qrcode.viewfinder")
                                    .font(.system(size: 18))
                                    .foregroundColor(Color.primaryFixed)
                                Text("SCAN QR CODE")
                                    .font(.labelCaps)
                                    .foregroundColor(Color.onSurfaceVariant)
                                    .tracking(4)
                            }

                            Button(action: { showScannerPlaceholder = true }) {
                                ZStack {
                                    Color.surfaceContainerLow

                                    // Corner brackets
                                    QRCornerBrackets()

                                    VStack(spacing: 8) {
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 36))
                                            .foregroundColor(Color.primaryFixed)
                                        Text("TAP TO SCAN")
                                            .font(.labelCaps)
                                            .foregroundColor(Color.primaryFixed)
                                            .tracking(4)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outlineVariant, lineWidth: 2))
                            }
                            .frame(maxWidth: 280)
                            .frame(maxWidth: .infinity)
                        }

                        // Join button
                        Button(action: { dismiss() }) {
                            HStack(spacing: 12) {
                                Text("JOIN RIDE")
                                    .font(.headlineMd)
                                    .tracking(4)
                                Image(systemName: "bolt.fill")
                            }
                            .modifier(LimePrimaryButton())
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.onPrimaryFixed.opacity(0.2), lineWidth: 4).padding(.top, 52))
                        }

                        HStack(spacing: 4) {
                            Text("Need help?")
                                .font(.bodyMd)
                                .foregroundColor(Color.onSurfaceVariant)
                            Text("Contact Support")
                                .font(.bodyMd)
                                .foregroundColor(Color.primaryFixed)
                                .underline()
                        }

                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }

                // Toast overlay
                if showToast {
                    VStack {
                        Spacer()
                        HStack(spacing: 16) {
                            ZStack {
                                Circle().fill(Color.primaryContainer).frame(width: 44, height: 44)
                                Image(systemName: "car.fill").foregroundColor(Color.onPrimaryContainer)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("CODE DETECTED").font(.labelCaps).foregroundColor(Color.primaryFixed).tracking(2)
                                Text("Validating squad \"Midnight Wolves\"...").font(.bodyMd).foregroundColor(Color.onSurface)
                            }
                            Spacer()
                        }
                        .padding(16)
                        .background(Color.surfaceContainerHighest)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primaryFixed.opacity(0.3), lineWidth: 1))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 100)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .animation(.spring(), value: showToast)
                }
            }
            .navigationTitle("JOIN RIDE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "arrow.left").foregroundColor(Color.primaryFixed)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "antenna.radiowaves.left.and.right").foregroundColor(Color.primaryFixed)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct QRCornerBrackets: View {
    let bracketSize: CGFloat = 32
    let lineWidth: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Top-left
                Path { p in
                    p.move(to: CGPoint(x: 16, y: 16 + bracketSize))
                    p.addLine(to: CGPoint(x: 16, y: 16))
                    p.addLine(to: CGPoint(x: 16 + bracketSize, y: 16))
                }.stroke(Color.primaryFixed, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                // Top-right
                Path { p in
                    p.move(to: CGPoint(x: geo.size.width - 16 - bracketSize, y: 16))
                    p.addLine(to: CGPoint(x: geo.size.width - 16, y: 16))
                    p.addLine(to: CGPoint(x: geo.size.width - 16, y: 16 + bracketSize))
                }.stroke(Color.primaryFixed, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                // Bottom-left
                Path { p in
                    p.move(to: CGPoint(x: 16, y: geo.size.height - 16 - bracketSize))
                    p.addLine(to: CGPoint(x: 16, y: geo.size.height - 16))
                    p.addLine(to: CGPoint(x: 16 + bracketSize, y: geo.size.height - 16))
                }.stroke(Color.primaryFixed, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                // Bottom-right
                Path { p in
                    p.move(to: CGPoint(x: geo.size.width - 16 - bracketSize, y: geo.size.height - 16))
                    p.addLine(to: CGPoint(x: geo.size.width - 16, y: geo.size.height - 16))
                    p.addLine(to: CGPoint(x: geo.size.width - 16, y: geo.size.height - 16 - bracketSize))
                }.stroke(Color.primaryFixed, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        }
    }
}

#Preview {
    JoinRideView()
}
