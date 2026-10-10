import Foundation

public enum VoiceLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case hindi = "hi", punjabi = "pa", english = "en"
    public var id: String { rawValue }
    public var name: String {
        switch self { case .hindi: return "हिन्दी"; case .punjabi: return "ਪੰਜਾਬੀ"; case .english: return "English" }
    }
    public var locale: String {
        switch self { case .hindi: return "hi-IN"; case .punjabi: return "pa-IN"; case .english: return "en-IN" }
    }
    public func text(for prompt: String) -> String {
        switch (self, prompt) {
        case (.hindi, "checkin"): return "भाई, आँखें बंद हो रही हैं। मेरी आवाज़ आ रही है? सुरक्षित जगह पर रुक कर आराम करो।"
        case (.punjabi, "checkin"): return "ਪਾਜੀ, ਅੱਖਾਂ ਬੰਦ ਹੋ ਰਹੀਆਂ ਨੇ। ਮੇਰੀ ਆਵਾਜ਼ ਸੁਣ ਰਹੇ ਹੋ? ਸੁਰੱਖਿਅਤ ਥਾਂ ਤੇ ਰੁਕ ਕੇ ਆਰਾਮ ਕਰੋ।"
        case (.hindi, "acknowledged"): return "ठीक है भाई। नींद आ रही है तो सुरक्षित जगह पर रुक कर आराम करो।"
        case (.punjabi, "acknowledged"): return "ਠੀਕ ਹੈ ਪਾਜੀ। ਨੀਂਦ ਆ ਰਹੀ ਹੈ ਤਾਂ ਸੁਰੱਖਿਅਤ ਥਾਂ ਤੇ ਰੁਕ ਕੇ ਆਰਾਮ ਕਰੋ।"
        case (.hindi, "critical"): return "भाई, अभी सुरक्षित जगह पर गाड़ी रोक कर आराम करो।"
        case (.punjabi, "critical"): return "ਪਾਜੀ, ਹੁਣ ਸੁਰੱਖਿਅਤ ਥਾਂ ਤੇ ਗੱਡੀ ਰੋਕ ਕੇ ਆਰਾਮ ਕਰੋ।"
        case (_, "acknowledged"): return "I hear you. If you feel sleepy, stop somewhere safe and rest."
        case (_, "critical"): return "Pull over somewhere safe and rest."
        default: return "Your eyes are closing. Can you hear me? Pull over somewhere safe and rest."
        }
    }
    public func acknowledges(_ transcript: String) -> Bool {
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let words = Set(transcript.lowercased().components(separatedBy: separators))
        let tokens: Set<String> = ["yes", "okay", "ok", "हाँ", "हां", "जी", "सुन", "ਹਾਂ", "ਜੀ", "ਸੁਣ", "haan", "han"]
        return !words.isDisjoint(with: tokens) || transcript.contains("ठीक") || transcript.contains("ਠੀਕ")
    }
}
