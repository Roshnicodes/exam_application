// One camera/mic stream shared across Turbo page visits (system check -> exam).
let stream

export async function getStream() {
  if (stream && stream.getVideoTracks().some((t) => t.readyState === "live")) return stream

  if (!navigator.mediaDevices?.getUserMedia) throw Object.assign(new Error("No camera API"), { name: "NoMediaApi" })
  const video = { width: { ideal: 640 }, height: { ideal: 480 }, facingMode: "user" }
  const audio = { echoCancellation: true, noiseSuppression: false }
  try {
    stream = await navigator.mediaDevices.getUserMedia({ video, audio })
  } catch (e) {
    if (e.name === "NotAllowedError" || e.name === "SecurityError") throw e
    // no microphone, or the camera can't do these settings / is busy: retry with simpler requests
    stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true })
      .catch(() => navigator.mediaDevices.getUserMedia({ video: true }))
      .catch(() => { throw e })
  }
  return stream
}

// Why the camera didn't start, in plain words, with what to do about it.
export function cameraHelp(error) {
  const ua = navigator.userAgent
  if (/WhatsApp|FBAN|FBAV|Instagram|Line\/|; wv\)/i.test(ua)) {
    return { short: "Open in Chrome", title: "Open this link in Chrome",
             help: "This link opened inside an app (e.g. WhatsApp), which can't use the camera. Tap ⋮ (top right) → “Open in Chrome” / “Open in browser”, or copy the link into Chrome." }
  }
  if (!window.isSecureContext) {
    return { short: "Not secure (https)", title: "Use the https:// link", help: "The camera only works on a secure https:// link. Open the exact link HR sent you." }
  }
  switch (error?.name) {
    case "NotAllowedError":
    case "SecurityError":
      return { short: "Permission blocked", title: "Camera permission is blocked",
               help: "Click the 🔒 / camera icon at the left of the address bar → set Camera and Microphone to “Allow” → reload the page. If it stays blocked, also allow the browser to use the camera in your computer's privacy settings (Windows: Settings → Privacy → Camera; Mac: System Settings → Privacy → Camera)." }
    case "NotReadableError":
    case "TrackStartError":
    case "AbortError":
      return { short: "Camera busy", title: "Camera is being used by another app",
               help: "Close Zoom, Teams, Meet, WhatsApp desktop or any other tab/app using the camera, then try again." }
    case "NotFoundError":
    case "DevicesNotFoundError":
    case "OverconstrainedError":
      return { short: "No camera found", title: "No camera found", help: "Connect a webcam (or use a laptop / phone with a camera) and try again." }
    case "NoMediaApi":
      return { short: "Browser not supported", title: "This browser can't use the camera", help: "Open the link in the latest Google Chrome or Microsoft Edge." }
    default:
      return { short: "Camera error", title: "Camera didn't start", help: `Reload the page and allow the camera. (${error?.name || "unknown error"})` }
  }
}

export function stopStream() {
  stream?.getTracks().forEach((t) => t.stop())
  stream = null
  stopScreen()
}

// ---- Entire-screen sharing (desktop only), shared by the test and the interview rooms ----
let screen

let shareImpossible = false

// Phones and tablets — also in Chrome's "Desktop site" mode, which hides "Mobile" in the user agent.
// A touchscreen laptop still has a mouse / trackpad ("pointer: fine"), so it counts as a computer.
export function isPhoneOrTablet() {
  return navigator.userAgentData?.mobile === true || /Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent) ||
    (navigator.maxTouchPoints > 1 && matchMedia("(pointer: coarse)").matches && !matchMedia("(any-pointer: fine)").matches)
}

// Browsers can share the screen only on a computer.
export function screenShareSupported() {
  return !shareImpossible && typeof navigator.mediaDevices?.getDisplayMedia === "function" && !isPhoneOrTablet()
}

// The share failed because this device can't share at all (not because the person pressed Cancel):
// from now on the test / interview carries on without screen sharing.
export function screenShareImpossible(error) {
  if ([ "NotSupportedError", "TypeError", "InvalidStateError" ].includes(error?.name)) shareImpossible = true
  return shareImpossible
}

export function getScreenStream() {
  return screen && screen.getVideoTracks().some((t) => t.readyState === "live") ? screen : null
}

// Opens the browser's share picker; only "Entire screen" is accepted.
export async function requestScreen() {
  const s = await navigator.mediaDevices.getDisplayMedia({
    video: { displaySurface: "monitor", frameRate: 5 }, audio: false,
    monitorTypeSurfaces: "include", selfBrowserSurface: "exclude", surfaceSwitching: "exclude"
  })
  const surface = s.getVideoTracks()[0]?.getSettings().displaySurface
  if (surface && surface !== "monitor") {
    s.getTracks().forEach((t) => t.stop())
    const error = new Error("Please choose “Entire screen” — not a window or a tab.")
    error.name = "NotEntireScreen"
    error.surface = surface
    throw error
  }
  screen = s
  return s
}

export function stopScreen() {
  screen?.getTracks().forEach((t) => t.stop())
  screen = null
}

export function snapshot(video, quality = 0.7) {
  return new Promise((resolve) => {
    if (!video || video.readyState < 2) return resolve(null)
    const canvas = document.createElement("canvas")
    canvas.width = 480
    canvas.height = Math.round(480 * (video.videoHeight / video.videoWidth || 0.75))
    canvas.getContext("2d").drawImage(video, 0, 0, canvas.width, canvas.height)
    canvas.toBlob((blob) => resolve(blob), "image/jpeg", quality)
  })
}

export function csrfToken() {
  return document.querySelector("meta[name='csrf-token']")?.content
}
