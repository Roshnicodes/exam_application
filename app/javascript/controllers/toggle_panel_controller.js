import { Controller } from "@hotwired/stimulus"

// Shows one of several collapsible panels (upload / add) at a time.
export default class extends Controller {
  static targets = [ "panel" ]

  connect() {
    this.openHandler = (e) => {
      const btn = e.target.closest("[data-action~='toggle-panel#open']")
      if (btn && !this.element.contains(btn)) this.open({ currentTarget: btn })
    }
    document.addEventListener("click", this.openHandler)
  }

  disconnect() {
    document.removeEventListener("click", this.openHandler)
  }

  open(event) {
    const id = event.currentTarget.dataset.panel
    this.panelTargets.forEach((p) => p.classList.toggle("hidden", p.id !== id || !p.classList.contains("hidden")))
    const shown = this.panelTargets.find((p) => p.id === id && !p.classList.contains("hidden"))
    shown?.scrollIntoView({ behavior: "smooth", block: "nearest" })
    shown?.querySelector("input:not([type=hidden]):not([type=file])")?.focus()
  }

  close(event) {
    event.currentTarget.closest("[data-toggle-panel-target='panel']").classList.add("hidden")
  }
}
