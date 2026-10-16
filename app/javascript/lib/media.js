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
