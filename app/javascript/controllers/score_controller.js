import { Controller } from "@hotwired/stimulus"

// Shows the number next to a 0-10 slider.
export default class extends Controller {
  static targets = [ "input", "out" ]

  show() {
    this.outTarget.textContent = this.inputTarget.value
  }
}
