import {mkdir, writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {voice} from './providers.mjs';

const prompts = {
  hi: {
    checkin: 'भाई, आँखें बंद हो रही हैं। मेरी आवाज़ आ रही है? सुरक्षित जगह पर रुक कर आराम करो।',
    acknowledged: 'ठीक है भाई। नींद आ रही है तो सुरक्षित जगह पर रुक कर आराम करो।',
    critical: 'भाई, अभी सुरक्षित जगह पर गाड़ी रोक कर आराम करो।'
  },
  pa: {
    checkin: 'ਪਾਜੀ, ਅੱਖਾਂ ਬੰਦ ਹੋ ਰਹੀਆਂ ਨੇ। ਮੇਰੀ ਆਵਾਜ਼ ਸੁਣ ਰਹੇ ਹੋ? ਸੁਰੱਖਿਅਤ ਥਾਂ ਤੇ ਰੁਕ ਕੇ ਆਰਾਮ ਕਰੋ।',
    acknowledged: 'ਠੀਕ ਹੈ ਪਾਜੀ। ਨੀਂਦ ਆ ਰਹੀ ਹੈ ਤਾਂ ਸੁਰੱਖਿਅਤ ਥਾਂ ਤੇ ਰੁਕ ਕੇ ਆਰਾਮ ਕਰੋ।',
    critical: 'ਪਾਜੀ, ਹੁਣ ਸੁਰੱਖਿਅਤ ਥਾਂ ਤੇ ਗੱਡੀ ਰੋਕ ਕੇ ਆਰਾਮ ਕਰੋ।'
  },
  en: {
    checkin: 'Your eyes are closing. Can you hear me? Pull over somewhere safe and rest.',
    acknowledged: 'I hear you. If you feel sleepy, stop somewhere safe and rest.',
    critical: 'Pull over somewhere safe and rest.'
  }
};
const dir = new URL('../iOS/JaagteRaho/Resources/Audio/', import.meta.url);
await mkdir(dir, {recursive: true});
let failures = 0;
for (const [language, lines] of Object.entries(prompts)) {
  for (const [name, text] of Object.entries(lines)) {
    try {
      const audio = await voice({key: process.env.SMALLEST_API_KEY, text, language});
      await writeFile(new URL(`${language}_${name}.wav`, dir), audio);
      console.log(`${language}_${name}.wav: ${audio.length} bytes, bundled for offline playback`);
    } catch (error) { failures++; console.error(`${language}_${name}: ${error.message}`); }
  }
}
if (failures) process.exitCode = 1;
