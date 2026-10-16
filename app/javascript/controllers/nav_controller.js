import { Controller } from "@hotwired/stimulus"

// Off-canvas sidebar on small screens.
export default class extends Controller {
  toggle() {
    this.element.classList.toggle("nav-open")
  }

  connect() {
    this.close = (e) => {
      if (this.element.classList.contains("nav-open") && !e.target.closest(".sidebar, .menu-btn")) this.element.classList.remove("nav-open")
    }
    document.addEventListener("click", this.close)
  }

  disconnect() {
    document.removeEventListener("click", this.close)
  }
}
