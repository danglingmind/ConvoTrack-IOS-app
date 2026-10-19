import SwiftUI

struct RiderDetailDrawer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sheetHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            riderHeader
                .padding(20)

            Rectangle()
                .fill(DS.Border.strongColor.opacity(0.2))
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
        .background(DS.Background.deep.ignoresSafeArea())
        .presentationDetents(sheetHeight > 0 ? [.height(sheetHeight)] : [.medium])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var riderHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            Circle()
                .fill(DS.Surface.card.base)
                .frame(width: 60, height: 60)
                .overlay(Circle().stroke(DS.Accent.base, lineWidth: 2))
                .overlay(
                    CachedImage(url: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuBlmttXTE0DMZ6BI0povBo7xzU813jzXL1XHG-dsBPoXXG-lUy3hEobK63F01CeBrI3qU7ccatWJoZZqf3VZSyIRORTX_8WCufPD0m471Hl6ef3-Pnlmy2uNCz2DV_MNTqqYvCHHxXQpEjjpFtO6l4cRPoT__c308QFkNUaGHbVDeuUP3FUBIXbQymlu8UOr5ETXl1l6VTtDPFob4iSalAQQgAcHZc3TmI8s-fRjUHGYkuntrVbaqjUOmrSB8le-GRLmmOjK4RVMsQ"), pointSize: 60) { img in
                        img.resizable().scaledToFill()
                    } placeholder: { DS.Surface.avatar }
                    .clipShape(Circle())
                )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("RIDER #2")
                        .dsText(.badge)
                        .foregroundColor(DS.Accent.base)
                        .tracking(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(DS.Accent.base.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Circle()
                        .fill(DS.Status.success)
                        .frame(width: 8, height: 8)
                        .shadow(color: DS.Status.success.opacity(0.6), radius: 4)
                }

                Text("SAM")
                    .dsText(.heroTitleCompact)
                    .foregroundColor(DS.Text.primary.base)

                Text("BMW R 1250 GS")
                    .dsText(.dataMono)
                    .foregroundColor(DS.Text.secondary.base)
            }

            Spacer()
        }
    }

    // MARK: - Telemetry

    private var telemetryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            TelemetryCard(label: "GAP DISTANCE", value: "+120", unit: "METERS", isPrimary: true)
            TelemetryCard(label: "CURRENT SPEED", value: "58", unit: "KM/H")
            TelemetryCard(label: "BATTERY", value: "76%", icon: "battery.75percent.bolt", iconColor: DS.Accent.base)
            TelemetryCard(label: "SIGNAL", value: "STRONG", icon: "wifi", iconColor: DS.Status.success)
        }
    }

    // MARK: - Report

    private var reportButton: some View {
        Button(action: {}) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 15, weight: .bold))
                Text("REPORT ISSUE")
                    .dsText(.badge)
                    .tracking(1)
            }
            .foregroundColor(DS.Status.danger)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(DS.Status.danger.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(DS.Status.danger.opacity(0.3), lineWidth: 1))
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
    var iconColor: Color = DS.Accent.base

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .dsText(.badge)
                .foregroundColor(DS.Text.secondary.base)

            if let icon {
                HStack(alignment: .center) {
                    Text(value)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(DS.Text.primary.base)
                    Spacer()
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(iconColor)
                }
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .foregroundColor(isPrimary ? DS.Accent.base : DS.Text.primary.base)
                    if let unit {
                        Text(unit)
                            .dsText(.badge)
                            .foregroundColor(DS.Text.secondary.base)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .background(DS.Surface.raised)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.Border.strongColor.opacity(0.3), lineWidth: 1))
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
