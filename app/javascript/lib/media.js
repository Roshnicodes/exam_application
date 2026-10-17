// One camera/mic stream shared across Turbo page visits (system check -> exam).
let stream

export async function getStream() {
  if (stream && stream.getVideoTracks().some((t) => t.readyState === "live")) return stream

  stream = await navigator.mediaDevices.getUserMedia({
    video: { width: { ideal: 640 }, height: { ideal: 480 }, facingMode: "user" },
    audio: { echoCancellation: true, noiseSuppression: false }
  })
  return stream
}

export function stopStream() {
  stream?.getTracks().forEach((t) => t.stop())
  stream = null
  stopScreen()
}

// ---- Entire-screen sharing (desktop only), shared by the test and the interview rooms ----
let screen

export function screenShareSupported() {
  return !!navigator.mediaDevices?.getDisplayMedia && !/Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent)
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
