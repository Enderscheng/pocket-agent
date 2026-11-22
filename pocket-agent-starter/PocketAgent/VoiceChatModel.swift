import Foundation
import Combine
import AVFoundation
import Speech
import Security
import UIKit

struct ChatMessage: Identifiable, Codable {
    var id = UUID()
    let role: String
    let content: String
    enum CodingKeys: String, CodingKey { case role, content }
}

enum VoiceKey {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "PocketAgent.voice",
         kSecAttrAccount as String: "phone"]
    }
    static func read() -> String? {
        var values = query
        values[kSecReturnData as String] = true
        values[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(values as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ key: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecItemNotFound {
            var values = query
            attributes.forEach { values[$0.key] = $0.value }
            guard SecItemAdd(values as CFDictionary, nil) == errSecSuccess else { throw ChatError.message("無法儲存連線密鑰，請重新解鎖再試。") }
        } else if update != errSecSuccess {
            throw ChatError.message("無法更新連線密鑰，請重新解鎖再試。")
        }
    }
    static func delete() { SecItemDelete(query as CFDictionary) }
}

enum ChatError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class VoiceChatModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let server = "https://pocket-agent-cloud.enderscheng.workers.dev"
    @Published var messages: [ChatMessage] = []
    @Published var draft = ""
    @Published var status = "準備好傾偈"
    @Published var errorMessage: String?
    @Published var isListening = false
    @Published var isThinking = false
    @Published var isSpeaking = false
    @Published var isStarting = false
    @Published var hasKey = VoiceKey.read() != nil
    @Published var autoListen = true
    @Published var sessionActive = false
    private let engine = AVAudioEngine()
    private let speaker = AVSpeechSynthesizer()
    private var recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-HK"))
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    private var tapInstalled = false
    private var silence: DispatchWorkItem?
    private var listenLimit: DispatchWorkItem?
    private var listenID: UUID?
    private var generation = UUID()
    private var requestTask: Task<Void, Never>?
    private var speechID: ObjectIdentifier?
    private let network = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)

    override init() {
        super.init()
        speaker.delegate = self
    }

    func saveKey(_ value: String) -> Bool {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.range(of: "^pv1_[a-f0-9]{64}$", options: .regularExpression) != nil else {
            errorMessage = "請貼上設定頁產生、以 pv1_ 開頭嘅語音密鑰。唔好用 ADMIN_TOKEN。"
            return false
        }
        do { try VoiceKey.save(key); hasKey = true; errorMessage = nil; return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
    func forgetKey() { stop(); VoiceKey.delete(); hasKey = false }

    func start() async {
        guard !isStarting, !isThinking, !isListening, !isSpeaking else { return }
        guard hasKey else { errorMessage = "請先喺設定貼上語音密鑰。"; return }
        let current = generation
        isStarting = true
        errorMessage = nil
        status = "檢查咪高峰權限…"
        let speech: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard current == generation else { return }
        guard speech == .authorized else {
            isStarting = false; status = "需要語音辨識權限"
            errorMessage = "請到 iPhone 設定 → Pocket Agent，開啟語音辨識權限。你亦可以打字。"; return
        }
        let microphone: Bool = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard current == generation else { return }
        isStarting = false
        guard microphone else {
            status = "需要咪高峰權限"
            errorMessage = "請到 iPhone 設定 → Pocket Agent，開啟咪高峰權限。你亦可以打字。"; return
        }
        guard UIApplication.shared.applicationState == .active else { status = "撳開始繼續"; return }
        sessionActive = true
        beginListening()
    }

    private func beginListening() {
        guard sessionActive, !isThinking, UIApplication.shared.applicationState == .active else { return }
        endListening()
        guard let recognizer = recognizer, recognizer.isAvailable else {
            fail("廣東話語音辨識暫時用唔到，請檢查網絡，或者用文字輸入。")
            return
        }
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audio.setActive(true)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw ChatError.message("搵唔到咪高峰，請檢查耳機連線。") }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            speechRequest = request
            let id = UUID()
            listenID = id
            draft = ""
            isListening = true
            status = "聆聽中 · 講完停頓兩秒就會傳送"
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            tapInstalled = true
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self = self, self.listenID == id else { return }
                    if let result = result {
                        self.draft = result.bestTranscription.formattedString
                        if self.draft.count > 3500 { self.finishSpeaking(); return }
                        self.silence?.cancel()
                        let wait = DispatchWorkItem { [weak self] in
                            guard let self = self, self.listenID == id else { return }
                            self.finishSpeaking()
                        }
                        self.silence = wait
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: wait)
                        if result.isFinal { self.finishSpeaking(); return }
                    }
                    if error != nil {
                        // Keep any partial transcription for review, never send on errors.
                        self.fail("語音辨識中斷。你可以修改下面嘅文字再傳送，或者重新開始。")
                    }
                }
            }
            engine.prepare()
            try engine.start()
            let limit = DispatchWorkItem { [weak self] in
                guard let self = self, self.listenID == id else { return }
                self.endListening(); self.sessionActive = false; self.status = "已暫停 · 撳開始繼續"
                self.errorMessage = "今次聆聽已暫停。已有嘅文字可以修改再傳送。"
            }
            listenLimit = limit
            DispatchQueue.main.asyncAfter(deadline: .now() + 50, execute: limit)
        } catch { fail(error.localizedDescription) }
    }

    private func endListening() {
        listenID = nil
        silence?.cancel(); silence = nil
        listenLimit?.cancel(); listenLimit = nil
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        speechRequest?.endAudio(); speechRequest = nil
        recognitionTask?.cancel(); recognitionTask = nil
        isListening = false
    }

    func finishSpeaking() {
        endListening()
        send()
    }
    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking, !isStarting else { return }
        guard text.utf16.count <= 4000 else { errorMessage = "呢段太長，請分開幾次講。"; return }
        guard let key = VoiceKey.read() else { hasKey = false; errorMessage = "請先設定語音密鑰。"; return }
        endListening()
        speechID = nil; speaker.stopSpeaking(at: .immediate); isSpeaking = false
        errorMessage = nil
        let history = Array(messages.suffix(10)) + [ChatMessage(role: "user", content: text)]
        // Keep complete exchanges, dropping the oldest pair until within server limits.
        var context = history
        while context.count > 1 && context.reduce(0, { $0 + $1.content.utf16.count }) > 20000 { context.removeFirst(2) }
        draft = ""
        isThinking = true
        status = "諗緊…"
        let current = generation
        requestTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                struct Payload: Encodable { let messages: [ChatMessage] }
                struct Reply: Decodable { let reply: String?; let error: String? }
                var request = URLRequest(url: URL(string: Self.server + "/api/chat")!)
                request.httpMethod = "POST"
                request.timeoutInterval = 60
                request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(Payload(messages: context))
                let (data, response) = try await self.network.data(for: request)
                guard current == self.generation, !Task.isCancelled else { return }
                guard let http = response as? HTTPURLResponse else { throw ChatError.message("伺服器回應無效。") }
                if http.statusCode == 404 { throw ChatError.message("雲端仲未更新。請等 Cloudflare 部署完成。") }
                let result = try JSONDecoder().decode(Reply.self, from: data)
                guard http.statusCode == 200, let answer = result.reply, !answer.isEmpty else {
                    if http.statusCode == 401 { self.hasKey = false }
                    throw ChatError.message(result.error ?? "暫時連唔到 AI，請稍後再試。")
                }
                self.messages.append(ChatMessage(role: "user", content: text))
                self.messages.append(ChatMessage(role: "assistant", content: answer))
                if self.messages.count > 50 { self.messages.removeFirst(2) }
                self.isThinking = false
                self.speak(answer)
            } catch {
                guard current == self.generation, !Task.isCancelled else { return }
                self.draft = text
                self.fail(error.localizedDescription)
            }
        }
    }

    private func speak(_ text: String) {
        guard UIApplication.shared.applicationState == .active else { stop(); return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { fail("回覆已顯示，但暫時播唔到聲音。"); return }
        let utterance = AVSpeechUtterance(string: text)
        let hasChinese = text.range(of: "[\\p{Han}]", options: .regularExpression) != nil
        let voice = AVSpeechSynthesisVoice(language: hasChinese ? "zh-HK" : "en-GB")
        guard let voice = voice else { fail("回覆已顯示。請喺 iPhone 下載廣東話朗讀聲音，再試語音回覆。"); return }
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speechID = ObjectIdentifier(utterance)
        isSpeaking = true
        status = "回答中…"
        speaker.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.speechID == id else { return }
            self.speechID = nil; self.isSpeaking = false; self.status = "準備好下一句"
            if self.sessionActive && self.autoListen {
                let current = self.generation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    guard let self = self, self.generation == current else { return }
                    self.beginListening()
                }
            } else { self.sessionActive = false }
        }
    }

    func interruptAndListen() {
        speechID = nil; speaker.stopSpeaking(at: .immediate); isSpeaking = false
        sessionActive = true
        beginListening()
    }
    func stop() {
        generation = UUID()
        sessionActive = false; isStarting = false
        requestTask?.cancel(); requestTask = nil
        endListening()
        speechID = nil; speaker.stopSpeaking(at: .immediate)
        isSpeaking = false; isThinking = false
        status = "已暫停"
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func clear() { stop(); messages = []; draft = ""; errorMessage = nil; status = "新對話" }
    private func fail(_ message: String) { stop(); errorMessage = message }
}
