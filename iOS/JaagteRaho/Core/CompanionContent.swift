import Foundation

public enum CompanionContent {
    public static func enrollment(_ step: CalibrationCollector.Phase, language: VoiceLanguage) -> String {
        switch (step, language) {
        case (.openEyes, .hindi): return "गाड़ी खड़ी रखें। फ़ोन की तरफ़ देखें और दोनों आँखें तीन सेकंड खुली रखें।"
        case (.closedEyes, .hindi): return "अब गाड़ी खड़ी रखते हुए दोनों आँखें धीरे से दो सेकंड बंद करें।"
        case (.complete, .hindi): return "आँखों की तैयारी पूरी हुई। आँखें खोलें, फिर निगरानी शुरू करने का बटन दबाएँ।"
        case (.openEyes, .punjabi): return "ਗੱਡੀ ਖੜ੍ਹੀ ਰੱਖੋ। ਫ਼ੋਨ ਵੱਲ ਵੇਖੋ ਤੇ ਦੋਵੇਂ ਅੱਖਾਂ ਤਿੰਨ ਸਕਿੰਟ ਖੁੱਲ੍ਹੀਆਂ ਰੱਖੋ।"
        case (.closedEyes, .punjabi): return "ਹੁਣ ਗੱਡੀ ਖੜ੍ਹੀ ਰੱਖਦੇ ਹੋਏ ਦੋਵੇਂ ਅੱਖਾਂ ਹੌਲੀ ਜਿਹੇ ਦੋ ਸਕਿੰਟ ਬੰਦ ਕਰੋ।"
        case (.complete, .punjabi): return "ਅੱਖਾਂ ਦੀ ਤਿਆਰੀ ਪੂਰੀ ਹੈ। ਅੱਖਾਂ ਖੋਲ੍ਹੋ, ਫਿਰ ਨਿਗਰਾਨੀ ਸ਼ੁਰੂ ਕਰਨ ਵਾਲਾ ਬਟਨ ਦਬਾਓ।"
        case (.openEyes, .english): return "Stay parked. Look at the phone with both eyes open for three seconds."
        case (.closedEyes, .english): return "Now, while parked, gently close both eyes for two seconds."
        case (.complete, .english): return "Your eye setup is complete. Open your eyes, then tap Start monitoring."
        }
    }
    public static func greeting(_ language: VoiceLanguage) -> String {
        switch language {
        case .hindi: return "नमस्ते भाई, मैं ओली हूँ। तुम्हारे सफ़र का साथी। बात करें, कहानी सुनें या छोटा सा क्विज़ खेलें?"
        case .punjabi: return "ਸਤਿ ਸ੍ਰੀ ਅਕਾਲ ਪਾਜੀ, ਮੈਂ ਓਲੀ ਹਾਂ। ਤੁਹਾਡੇ ਸਫ਼ਰ ਦਾ ਸਾਥੀ। ਗੱਲ ਕਰੀਏ, ਕਹਾਣੀ ਸੁਣੀਏ ਜਾਂ ਛੋਟਾ ਜਿਹਾ ਕੁਇਜ਼ ਖੇਡੀਏ?"
        case .english: return "Hello, I'm Ollie, your road companion. We can talk, listen to a story, or try a quick quiz."
        }
    }
    public static func story(_ language: VoiceLanguage) -> String {
        switch language {
        case .hindi: return "एक ट्रक चालक हर सफ़र में चाय की दुकान पर एक पौधे को पानी देता था। एक दिन दुकान बंद मिली, लेकिन पौधे के पास पानी की बोतल रखी थी। दुकानदार ने पर्ची छोड़ी थी: तुम रास्ते में सबका ध्यान रखते हो, आज अपना भी रखना। चालक मुस्कुराया और वहीं रुक कर आराम किया। कभी कभी सफ़र की सबसे अच्छी मंज़िल एक छोटा सा विराम होती है।"
        case .punjabi: return "ਇੱਕ ਟਰੱਕ ਚਾਲਕ ਹਰ ਸਫ਼ਰ ਵਿੱਚ ਚਾਹ ਦੀ ਦੁਕਾਨ ਦੇ ਬੂਟੇ ਨੂੰ ਪਾਣੀ ਦਿੰਦਾ ਸੀ। ਇੱਕ ਦਿਨ ਦੁਕਾਨ ਬੰਦ ਸੀ, ਪਰ ਬੂਟੇ ਕੋਲ ਪਾਣੀ ਦੀ ਬੋਤਲ ਸੀ। ਦੁਕਾਨਦਾਰ ਨੇ ਲਿਖਿਆ ਸੀ: ਤੁਸੀਂ ਸਭ ਦਾ ਖ਼ਿਆਲ ਰੱਖਦੇ ਹੋ, ਅੱਜ ਆਪਣਾ ਵੀ ਰੱਖੋ। ਚਾਲਕ ਮੁਸਕਰਾਇਆ ਤੇ ਉੱਥੇ ਰੁਕ ਕੇ ਆਰਾਮ ਕੀਤਾ। ਕਈ ਵਾਰ ਸਫ਼ਰ ਦੀ ਸਭ ਤੋਂ ਵਧੀਆ ਮੰਜ਼ਿਲ ਇੱਕ ਛੋਟਾ ਜਿਹਾ ਵਿਰਾਮ ਹੁੰਦੀ ਹੈ।"
        case .english: return "A truck driver watered a little plant outside a tea stall on every journey. One day the stall was closed, but a bottle waited beside the plant. The owner's note said: You look after everyone along the road. Today, look after yourself too. The driver smiled and stopped for a rest. Sometimes the best part of a journey is a little pause along the way."
        }
    }
    public static func quiz(_ language: VoiceLanguage) -> String {
        switch language {
        case .hindi: return "छोटा सा क्विज़: लाल ग्रह किसे कहते हैं? अपना जवाब बोलो।"
        case .punjabi: return "ਛੋਟਾ ਜਿਹਾ ਕੁਇਜ਼: ਲਾਲ ਗ੍ਰਹਿ ਕਿਹੜਾ ਹੈ? ਆਪਣਾ ਜਵਾਬ ਬੋਲੋ।"
        case .english: return "A quick quiz: which planet is known as the red planet? Say your answer."
        }
    }
    public static func quizReply(_ answer: String, language: VoiceLanguage) -> String {
        let correct = ["mars", "मंगल", "ਮੰਗਲ"].contains { answer.lowercased().contains($0) }
        switch language {
        case .hindi: return correct ? "बिल्कुल सही, मंगल! उसकी लाल मिट्टी से यह नाम मिला है।" : "जवाब है मंगल। उसकी लाल मिट्टी से उसे लाल ग्रह कहते हैं।"
        case .punjabi: return correct ? "ਬਿਲਕੁਲ ਸਹੀ, ਮੰਗਲ! ਉਸਦੀ ਲਾਲ ਮਿੱਟੀ ਤੋਂ ਇਹ ਨਾਮ ਮਿਲਿਆ ਹੈ।" : "ਜਵਾਬ ਹੈ ਮੰਗਲ। ਉਸਦੀ ਲਾਲ ਮਿੱਟੀ ਤੋਂ ਉਸਨੂੰ ਲਾਲ ਗ੍ਰਹਿ ਕਹਿੰਦੇ ਹਨ।"
        case .english: return correct ? "That's right, Mars! Iron minerals in its soil give it that rusty red color." : "The answer is Mars. Iron minerals in its soil give it that rusty red color."
        }
    }
    public static func reply(_ message: String, language: VoiceLanguage) -> String {
        let sleepy = ["sleep", "tired", "नींद", "थक", "ਨੀਂਦ", "ਥੱਕ"].contains { message.lowercased().contains($0) }
        if sleepy { return language.text(for: "critical") }
        switch language {
        case .hindi: return "मैं साथ हूँ भाई। मुझे कहानी सुनाने या क्विज़ खेलने को कह सकते हो। सफ़र कैसा चल रहा है?"
        case .punjabi: return "ਮੈਂ ਨਾਲ ਹਾਂ ਪਾਜੀ। ਮੈਨੂੰ ਕਹਾਣੀ ਸੁਣਾਉਣ ਜਾਂ ਕੁਇਜ਼ ਖੇਡਣ ਲਈ ਕਹਿ ਸਕਦੇ ਹੋ। ਸਫ਼ਰ ਕਿਵੇਂ ਚੱਲ ਰਿਹਾ ਹੈ?"
        case .english: return "I'm here with you. Ask me for a story or a quiz. How has your journey been?"
        }
    }
}
