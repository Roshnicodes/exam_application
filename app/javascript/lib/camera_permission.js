// Getting candidates past camera / microphone permission problems:
// - permissionState(): "granted" | "denied" | "prompt" | "unknown" (no reload needed to know)
// - watchPermission(cb): calls cb() as soon as camera access is allowed (no reload)
// - guideHtml(error): step-by-step fix for this candidate's browser / device, English + Hindi
import { cameraHelp } from "lib/media"

export async function permissionState() {
  try {
    const [ cam, mic ] = await Promise.all([ "camera", "microphone" ].map((name) => navigator.permissions.query({ name })))
    if (cam.state === "denied" || mic.state === "denied") return "denied"
    if (cam.state === "granted") return "granted"
    return "prompt"
  } catch {
    return "unknown" // Safari / Firefox don't report it
  }
}

// Fires once when camera (and mic) become allowed in the browser's site settings.
export async function watchPermission(onAllowed) {
  try {
    const statuses = await Promise.all([ "camera", "microphone" ].map((name) => navigator.permissions.query({ name })))
    const check = () => {
      if (statuses.every((s) => s.state !== "denied") && statuses[0].state === "granted") {
        statuses.forEach((s) => { s.onchange = null })
        onAllowed()
      }
    }
    statuses.forEach((s) => { s.onchange = check })
    return () => statuses.forEach((s) => { s.onchange = null })
  } catch {
    return () => {}
  }
}

const ua = () => navigator.userAgent
const isIOS = () => /iPhone|iPad|iPod/i.test(ua()) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)
const isAndroid = () => /Android/i.test(ua())
const isMac = () => /Macintosh|Mac OS X/i.test(ua()) && !isIOS()
const isWindows = () => /Windows/i.test(ua())
const isEdge = () => /Edg\//.test(ua())
const isFirefox = () => /Firefox\//.test(ua())
const isChromeIOS = () => /CriOS/.test(ua())

// The computer / phone itself blocks the browser (not the website)
export function blockedBySystem(error) {
  return /system/i.test(error?.message || "") || (isWindows() && error?.name === "NotReadableError" && /permission|denied/i.test(error?.message || ""))
}

function steps(error) {
  const name = error?.name
  const browser = isEdge() ? "Edge" : "Chrome"

  if (name === "NotAllowedError" || name === "SecurityError") {
    if (blockedBySystem(error)) {
      if (isWindows()) return [
        [ "Press the Windows <b>Start</b> button → open <b>Settings</b> → <b>Privacy &amp; security</b> → <b>Camera</b>.", "Start → Settings → Privacy &amp; security → Camera खोलें।" ],
        [ "Turn <b>ON</b>: “Camera access”, “Let apps access your camera” and “Let desktop apps access your camera”.", "तीनों बटन <b>ON</b> करें।" ],
        [ "Do the same under <b>Microphone</b>.", "<b>Microphone</b> में भी यही करें।" ],
        [ `Come back here and press <b>Try again</b>.`, "यहाँ वापस आकर <b>Try again</b> दबाएँ।" ]
      ]
      if (isMac()) return [
        [ "Open <b>System Settings</b> → <b>Privacy &amp; Security</b> → <b>Camera</b>.", "System Settings → Privacy &amp; Security → Camera खोलें।" ],
        [ `Turn on <b>${browser}</b>. Do the same under <b>Microphone</b>.`, `<b>${browser}</b> को ON करें, Microphone में भी।` ],
        [ `Quit and reopen ${browser}, then open the test link again.`, `${browser} बंद करके फिर खोलें और लिंक दोबारा खोलें।` ]
      ]
      if (isAndroid()) return [
        [ "Open phone <b>Settings</b> → <b>Apps</b> → <b>Chrome</b> → <b>Permissions</b>.", "फ़ोन Settings → Apps → Chrome → Permissions खोलें।" ],
        [ "Set <b>Camera</b> and <b>Microphone</b> to <b>Allow</b>.", "Camera और Microphone को <b>Allow</b> करें।" ],
        [ "Come back here and press <b>Try again</b>.", "वापस आकर <b>Try again</b> दबाएँ।" ]
      ]
    }
    if (isIOS()) {
      if (isChromeIOS()) return [
        [ "Open the iPhone <b>Settings</b> app → scroll to <b>Chrome</b>.", "iPhone Settings → Chrome खोलें।" ],
        [ "Turn on <b>Camera</b> and <b>Microphone</b>.", "Camera और Microphone ON करें।" ],
        [ "Come back and reload this page.", "वापस आकर पेज रीलोड करें।" ]
      ]
      return [
        [ "Tap <b>aA</b> (or the ⋯ icon) in the address bar → <b>Website Settings</b>.", "एड्रेस बार में <b>aA</b> → <b>Website Settings</b> दबाएँ।" ],
        [ "Set <b>Camera</b> and <b>Microphone</b> to <b>Allow</b>.", "Camera और Microphone को <b>Allow</b> करें।" ],
        [ "Reload the page. If it still fails: iPhone Settings → Safari → Camera → Allow.", "पेज रीलोड करें। फिर भी न हो तो Settings → Safari → Camera → Allow।" ]
      ]
    }
    if (isAndroid()) return [
      [ "Tap the <b>🔒 / ⚙</b> icon left of the web address.", "वेब एड्रेस के बाईं ओर <b>🔒</b> आइकन दबाएँ।" ],
      [ "Tap <b>Permissions</b> → set <b>Camera</b> and <b>Microphone</b> to <b>Allow</b>.", "<b>Permissions</b> → Camera और Microphone <b>Allow</b> करें।" ],
      [ "The page continues by itself — or press <b>Try again</b>.", "पेज अपने-आप आगे बढ़ेगा — या <b>Try again</b> दबाएँ।" ]
    ]
    if (isFirefox()) return [
      [ "Click the <b>camera icon with a line</b> in the address bar.", "एड्रेस बार में कटे हुए कैमरा आइकन पर क्लिक करें।" ],
      [ "Click <b>×</b> next to “Blocked” for camera and microphone.", "Camera / Microphone के “Blocked” के पास <b>×</b> दबाएँ।" ],
      [ "Reload the page and click <b>Allow</b>.", "पेज रीलोड करके <b>Allow</b> दबाएँ।" ]
    ]
    return [
      [ `Click the <b>camera icon with a red ✕</b> at the right end of the address bar (or the <b>🔒 / ⚙</b> icon at the left).`, "एड्रेस बार में लाल ✕ वाले कैमरा आइकन (या बाईं ओर 🔒) पर क्लिक करें।" ],
      [ "Choose <b>“Always allow … camera and microphone”</b> → <b>Done</b>. (Or set Camera and Microphone to <b>Allow</b>.)", "<b>Always allow</b> चुनें → <b>Done</b> दबाएँ।" ],
      [ "The camera starts by itself — or press <b>Try again</b>.", "कैमरा अपने-आप चालू होगा — या <b>Try again</b> दबाएँ।" ]
    ]
  }
  if (name === "NotReadableError" || name === "TrackStartError" || name === "AbortError") return [
    [ "Close <b>Zoom, Teams, Meet, WhatsApp, Camera app</b> and other browser tabs that use the camera.", "Zoom, Teams, Meet, WhatsApp, Camera ऐप और कैमरा वाले दूसरे टैब बंद करें।" ],
    [ "Press <b>Try again</b>. Still busy? Restart the browser (or the computer).", "<b>Try again</b> दबाएँ। फिर भी न हो तो ब्राउज़र/कंप्यूटर रीस्टार्ट करें।" ]
  ]
  if (name === "NotFoundError" || name === "DevicesNotFoundError" || name === "OverconstrainedError") return [
    [ "Connect a webcam, or use a laptop / phone that has a camera.", "वेबकैम लगाएँ या कैमरा वाला लैपटॉप / फ़ोन इस्तेमाल करें।" ],
    [ "On a laptop, check the camera isn't switched off by a key (often <b>F8 / F10</b> or a slider on the camera).", "लैपटॉप में कैमरा बटन / स्लाइडर (F8 / F10) बंद तो नहीं है, देखें।" ]
  ]
  return []
}

export function guideHtml(error) {
  const help = cameraHelp(error)
  const title = blockedBySystem(error) ? "Your computer / phone is blocking the camera" : help.title
  const list = steps(error)
  const items = list.length
    ? `<ol>${list.map(([ en, hi ]) => `<li>${en}<small>${hi}</small></li>`).join("")}</ol>`
    : `<span>${help.help}</span>`
  return `<b>${title}</b>${items}`
}

// Shown while the browser's own permission popup is open, pointing at it.
export const PROMPT_HINT = `<b>Your browser is asking for permission</b><ol><li>Look at the <b>top of the screen</b> (near the address bar) for a small popup.<small>स्क्रीन के ऊपर (एड्रेस बार के पास) एक छोटा पॉपअप दिखेगा।</small></li><li>Click <b>Allow</b> for camera and microphone — not “Block”.<small>कैमरा और माइक के लिए <b>Allow</b> दबाएँ — “Block” नहीं।</small></li></ol>`
