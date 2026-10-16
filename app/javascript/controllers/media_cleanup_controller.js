import { Controller } from "@hotwired/stimulus"
import { stopStream } from "lib/media"

// Turns the camera off and leaves full screen once the exam is over.
export default class extends Controller {
  connect() {
    stopStream()
    if (document.fullscreenElement) document.exitFullscreen().catch(() => {})
  }
}
