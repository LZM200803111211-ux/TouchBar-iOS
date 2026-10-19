import SwiftUI

struct TBKey: Identifiable {
    let id = UUID()
    let icon: String
    let cmd: String
}

// 第三排：可滑动的图标流
let KEYS: [TBKey] = [
    .init(icon: "speaker.slash.fill",         cmd: "mute"),
    .init(icon: "mic.slash.fill",             cmd: "muteMic"),
    .init(icon: "display",                    cmd: "alttab"),
    .init(icon: "rectangle.on.rectangle",     cmd: "showdesk"),
    .init(icon: "lock.fill",                  cmd: "lock"),
    .init(icon: "camera.fill",                cmd: "shot"),
    .init(icon: "scissors",                   cmd: "cut"),
    .init(icon: "doc.on.doc",                 cmd: "copy"),
    .init(icon: "doc.on.clipboard",           cmd: "paste"),
    .init(icon: "arrow.uturn.backward",       cmd: "undo"),
    .init(icon: "arrow.uturn.forward",        cmd: "redo"),
    .init(icon: "trash.fill",                 cmd: "recycle"),
    .init(icon: "music.note",                 cmd: "music"),
    .init(icon: "bubble.left.and.bubble.right.fill", cmd: "wechat"),
    .init(icon: "safari.fill",                cmd: "browser"),
    .init(icon: "chevron.left",               cmd: "pgup"),
    .init(icon: "chevron.right",              cmd: "pgdn"),
    .init(icon: "power",                      cmd: "sleep"),
]
