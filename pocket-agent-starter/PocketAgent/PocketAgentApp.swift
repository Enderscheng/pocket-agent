import SwiftUI
import AppIntents
import AVFoundation

@main
struct PocketAgentApp: App {
    init() { PocketAgentShortcuts.updateAppShortcutParameters() }
    var body: some Scene { WindowGroup { VoiceChatView() } }
}

struct VoiceChatView: View {
    @StateObject private var chat = VoiceChatModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var keyDraft = ""
    @FocusState private var typing: Bool
    @State private var showClearConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: chat.isListening ? "mic.fill" : "bubble.left.and.bubble.right.fill")
                    Text(chat.status).font(.subheadline)
                    if chat.isThinking || chat.isStarting { ProgressView() }
                    Spacer()
                }
                .foregroundStyle(chat.isListening ? Color.red : Color.accentColor)
                .accessibilityElement(children: .combine)
                Text("對話模式 · 可以傾偈同草擬內容，暫未連接日曆、提醒或 Obsidian 儲存。")
                    .font(.caption).foregroundStyle(.secondary)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if chat.messages.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("想傾啲咩？").font(.title2.bold())
                                    Text("例如：幫我諗下點安排今日嘅學習時間。")
                                    Text("講完停頓兩秒，助手就會回答。最近五輪對話會用作理解下一句。")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }.padding(.vertical, 30)
                            }
                            ForEach(chat.messages) { message in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(message.role == "user" ? "你" : "Pocket Agent")
                                        .font(.caption.bold()).foregroundStyle(.secondary)
                                    Text(message.content).textSelection(.enabled)
                                }
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(message.role == "user" ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .id(message.id)
                            }
                        }
                    }
                    .onChange(of: chat.messages.count) { _ in
                        if let last = chat.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                if let error = chat.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red).textSelection(.enabled)
                }
                if !chat.hasKey {
                    Button("設定語音連線") { openSettings() }.buttonStyle(.borderedProminent)
                }
                TextField(chat.isListening ? "聽到嘅內容…" : "亦可以喺呢度打字", text: $chat.draft, axis: .vertical)
                    .lineLimit(1...4).textFieldStyle(.roundedBorder).focused($typing)
                    .disabled(chat.isListening || chat.isThinking || chat.isStarting)
                HStack {
                    if chat.isListening {
                        Button { chat.finishSpeaking() } label: { Label("講完，傳送", systemImage: "arrow.up.circle.fill") }
                            .buttonStyle(.borderedProminent)
                    } else if chat.isSpeaking {
                        Button { typing = false; chat.interruptAndListen() } label: { Label("到我講", systemImage: "mic.fill") }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button { typing = false; Task { await chat.start() } } label: { Label("開始傾偈", systemImage: "mic.fill") }
                            .buttonStyle(.borderedProminent)
                            .disabled(!chat.hasKey || chat.isThinking || chat.isStarting)
                        Button("傳送文字") { typing = false; chat.send() }
                            .disabled(chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !chat.hasKey || chat.isThinking || chat.isStarting)
                    }
                    Spacer()
                    Button("停止", role: .destructive) { chat.stop() }
                        .disabled(!chat.sessionActive && !chat.isThinking && !chat.isSpeaking && !chat.isStarting)
                }
                Toggle("回答後自動再聆聽", isOn: $chat.autoListen).font(.footnote)
                Text("離開 App 或鎖屏會停止。語音辨識可能經 Apple 處理；文字會傳到你嘅 Cloudflare AI。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("語音助手")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("新對話") { showClearConfirmation = true } }
                ToolbarItem(placement: .navigationBarTrailing) { Button("設定") { openSettings() } }
            }
            .confirmationDialog("清除呢個 App 畫面嘅對話？", isPresented: $showClearConfirmation, titleVisibility: .visible) {
                Button("清除並開始新對話", role: .destructive) { chat.clear() }
            }
            .sheet(isPresented: $showSettings) { settings }
            .onAppear { consumeVoiceRequest() }
            .onChange(of: scenePhase) { phase in
                if phase == .active { consumeVoiceRequest() }
                if phase == .background { chat.stop() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pocketVoiceRequested)) { _ in consumeVoiceRequest() }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in chat.stop() }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
                if let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                   reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { chat.stop() }
            }
        }
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Section("連接你嘅雲端助手") {
                    Text(VoiceChatModel.server).font(.footnote).textSelection(.enabled)
                    Link("開啟設定頁並產生語音密鑰", destination: URL(string: VoiceChatModel.server + "/admin")!)
                    Text("用 ADMIN_TOKEN 登入網頁後，按 Create voice key。只將新產生、以 pv1_ 開頭嘅密鑰貼喺下面。")
                    SecureField("Voice key (pv1_…)", text: $keyDraft)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("儲存連線密鑰") {
                        if chat.saveKey(keyDraft) { keyDraft = ""; showSettings = false }
                    }
                    if let error = chat.errorMessage { Text(error).foregroundStyle(.red).font(.footnote) }
                    if chat.hasKey { Button("移除此機密鑰", role: .destructive) { chat.forgetKey(); keyDraft = "" } }
                }
                Section("廣東話 Siri") {
                    Text("打開「捷徑」，新增捷徑，加入 Pocket Agent 嘅 Start Voice Chat 動作。將捷徑命名為「同助手傾偈」。")
                    Text("之後講：Siri，同助手傾偈。iPhone 會要求解鎖，再打開對話。首次請先喺 App 批准咪高峰及語音辨識權限。")
                    Button("重新註冊 Siri 動作") { PocketAgentShortcuts.updateAppShortcutParameters() }
                }
                Section("關於") {
                    Text("語音對話 0.2 · 使用 Cloudflare Workers AI，並非登入你嘅 ChatGPT 或 Codex 帳戶。")
                    Text("助手只收到最近五輪對話，冇你其他聊天或檔案嘅內容。對話只保留喺 App 記憶體；唔會寫入你嘅雲端資料庫。")
                    Text("每分鐘最多 8 次、每日 UTC 最多 100 次請求；Cloudflare 免費額度可能更早用完。")
                }
            }.navigationTitle("語音設定")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { keyDraft = ""; showSettings = false } } }
        }
    }
    private func openSettings() { chat.stop(); typing = false; keyDraft = ""; showSettings = true }
    private func consumeVoiceRequest() {
        guard scenePhase == .active, UserDefaults.standard.bool(forKey: "startVoiceChat") else { return }
        UserDefaults.standard.removeObject(forKey: "startVoiceChat")
        showSettings = false; typing = false
        Task { await chat.start() }
    }
}
