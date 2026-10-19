import SwiftUI

struct BarView: View {
    @StateObject private var ble = BLE()
    @State private var vol: Double = 0.5
    @State private var bri: Double = 0.7

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                nowPlaying.frame(height: 96)
                Divider().overlay(Color.white.opacity(0.08))
                sliders.frame(height: 66)
                Divider().overlay(Color.white.opacity(0.08))
                keys.frame(maxHeight: .infinity)
                Divider().overlay(Color.white.opacity(0.08))
                stats.frame(height: 44)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear { ble.start() }
    }

    // ---------- 1. 当前播放 ----------
    private var nowPlaying: some View {
        HStack(spacing: 14) {
            coverView

            VStack(alignment: .leading, spacing: 3) {
                Text(ble.title.isEmpty ? "未在播放" : ble.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(ble.artist.isEmpty ? "—" : ble.artist)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 26) {
                transport("backward.fill", "prev")
                transport(ble.playing ? "pause.fill" : "play.fill", "play", big: true)
                transport("forward.fill", "next")
            }
            .padding(.trailing, 4)
        }
        .padding(.horizontal, 18)
    }

    private func transport(_ icon: String, _ cmd: String, big: Bool = false) -> some View {
        Button { ble.send(cmd) } label: {
            Image(systemName: icon)
                .font(.system(size: big ? 26 : 19, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: big ? 44 : 34, height: 44)
        }
        .buttonStyle(PlainButtonStyle())
    }


    @ViewBuilder
    private var coverView: some View {
        // 圆角卡片 + 阴影（苹果风）
        Group {
            if ble.cover.isEmpty {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.16), Color.white.opacity(0.06)],
                            startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .overlay(
                        Image(systemName: ble.playing ? "waveform" : "music.note")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.white.opacity(0.45))
                    )
            } else {
                AsyncImage(url: URL(string: ble.cover)) { phase in
                    if let img = phase.image {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white.opacity(0.3))
                            )
                    }
                }
            }
        }
        .frame(width: 62, height: 62)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        // 内描边：让封面边缘有金属质感
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        // 投影：苹果那种柔和偏下的阴影
        .shadow(color: .black.opacity(0.55), radius: 10, x: 0, y: 4)
        .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
    }

    // ---------- 2. 音量 / 亮度 ----------
    private var sliders: some View {
        HStack(spacing: 18) {
            slider(icon: "speaker.fill", value: $vol, cmd: "volset")
            slider(icon: "sun.max.fill", value: $bri, cmd: "briset")
        }
        .padding(.horizontal, 18)
    }

    private func slider(icon: String, value: Binding<Double>, cmd: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
                .frame(width: 18)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12)).frame(height: 6)
                    Capsule()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: max(6, geo.size.width * value.wrappedValue), height: 6)
                }
                .frame(height: 22)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    let v = min(1, max(0, g.location.x / geo.size.width))
                    value.wrappedValue = v
                    ble.send(cmd + ":" + String(Int(v * 100)))
                })
            }
            .frame(height: 22)
        }
    }

    // ---------- 3. 图标流（可横滑） ----------
    private var keys: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(KEYS) { k in
                    Button { ble.send(k.cmd) } label: {
                        Image(systemName: k.icon)
                            .font(.system(size: 20, weight: .regular))
                            .foregroundColor(.white.opacity(0.9))
                            .frame(width: 52, height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // ---------- 4. CPU / GPU / 内存 ----------
    private var stats: some View {
        HStack(spacing: 22) {
            stat("cpu", ble.cpu)
            stat("cpu", ble.gpu, label: "GPU")
            HStack(spacing: 6) {
                Text("RAM")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
                Text(ble.ramText.isEmpty ? "—" : ble.ramText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
            }
            Spacer()
            HStack(spacing: 5) {
                Circle()
                    .fill(ble.connected ? Color.white : Color.white.opacity(0.22))
                    .frame(width: 6, height: 6)
                Text(ble.connected ? "已连接" : "等待连接")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(ble.connected ? 0.75 : 0.3))
            }
        }
        .padding(.horizontal, 18)
    }

    private func stat(_ icon: String, _ v: Double, label: String? = nil) -> some View {
        HStack(spacing: 6) {
            Text(label ?? "CPU")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(.white.opacity(0.35))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1)).frame(height: 4)
                    Capsule().fill(Color.white.opacity(0.8))
                        .frame(width: max(3, g.size.width * min(1, v / 100)), height: 4)
                }
                .frame(height: 10)
            }
            .frame(width: 46, height: 10)
            Text(String(format: "%.0f%%", v))
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 32, alignment: .leading)
        }
    }
}
