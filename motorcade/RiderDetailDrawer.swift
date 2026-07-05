import SwiftUI

struct RiderDetailDrawer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sheetHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            riderHeader
                .padding(20)

            Rectangle()
                .fill(Color.outlineVariant.opacity(0.2))
                .frame(height: 1)
                .padding(.horizontal, 20)

            telemetryGrid
                .padding(20)

            reportButton
                .padding(.horizontal, 20)
                .padding(.bottom, 48)
        }
        .background(
            GeometryReader { geo in
                Color.clear.onAppear { sheetHeight = geo.size.height }
            }
        )
        .background(Color.surfaceContainerLowest.ignoresSafeArea())
        .presentationDetents(sheetHeight > 0 ? [.height(sheetHeight)] : [.medium])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var riderHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            Circle()
                .fill(Color.surfaceContainer)
                .frame(width: 60, height: 60)
                .overlay(Circle().stroke(Color.primaryFixed, lineWidth: 2))
                .overlay(
                    AsyncImage(url: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuBlmttXTE0DMZ6BI0povBo7xzU813jzXL1XHG-dsBPoXXG-lUy3hEobK63F01CeBrI3qU7ccatWJoZZqf3VZSyIRORTX_8WCufPD0m471Hl6ef3-Pnlmy2uNCz2DV_MNTqqYvCHHxXQpEjjpFtO6l4cRPoT__c308QFkNUaGHbVDeuUP3FUBIXbQymlu8UOr5ETXl1l6VTtDPFob4iSalAQQgAcHZc3TmI8s-fRjUHGYkuntrVbaqjUOmrSB8le-GRLmmOjK4RVMsQ")) { img in
                        img.resizable().scaledToFill()
                    } placeholder: { Color.surfaceVariant }
                    .clipShape(Circle())
                )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("RIDER #2")
                        .font(.labelCaps)
                        .foregroundColor(Color.primaryFixed)
                        .tracking(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primaryFixed.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Circle()
                        .fill(Color.tertiaryFixed)
                        .frame(width: 8, height: 8)
                        .shadow(color: Color.tertiaryFixed.opacity(0.6), radius: 4)
                }

                Text("SAM")
                    .font(.headlineLg)
                    .foregroundColor(Color.onSurface)

                Text("BMW R 1250 GS")
                    .font(.dataMono)
                    .foregroundColor(Color.onSurfaceVariant)
            }

            Spacer()
        }
    }

    // MARK: - Telemetry

    private var telemetryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            TelemetryCard(label: "GAP DISTANCE", value: "+120", unit: "METERS", isPrimary: true)
            TelemetryCard(label: "CURRENT SPEED", value: "58", unit: "KM/H")
            TelemetryCard(label: "BATTERY", value: "76%", icon: "battery.75percent.bolt", iconColor: Color.primaryFixed)
            TelemetryCard(label: "SIGNAL", value: "STRONG", icon: "wifi", iconColor: Color.tertiaryFixed)
        }
    }

    // MARK: - Report

    private var reportButton: some View {
        Button(action: {}) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 15, weight: .bold))
                Text("REPORT ISSUE")
                    .font(.labelCaps)
                    .tracking(1)
            }
            .foregroundColor(Color.errorColor)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.errorColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.errorColor.opacity(0.3), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(DrawerButtonStyle())
    }
}

// MARK: - Telemetry Card

struct TelemetryCard: View {
    let label: String
    let value: String
    var unit: String? = nil
    var isPrimary: Bool = false
    var icon: String? = nil
    var iconColor: Color = Color.primaryFixed

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.labelCaps)
                .foregroundColor(Color.onSurfaceVariant)

            if let icon {
                HStack(alignment: .center) {
                    Text(value)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.onSurface)
                    Spacer()
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(iconColor)
                }
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .foregroundColor(isPrimary ? Color.primaryFixed : Color.onSurface)
                    if let unit {
                        Text(unit)
                            .font(.labelCaps)
                            .foregroundColor(Color.onSurfaceVariant)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.surfaceContainerHigh)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))
    }
}

private struct DrawerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.08 : 0))
                    .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            )
    }
}

#Preview {
    RiderDetailDrawer()
}
