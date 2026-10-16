import { Controller } from "@hotwired/stimulus"

// Add / remove question blocks in the question paper builder.
export default class extends Controller {
  static targets = [ "list", "template", "item", "destroy", "position", "number" ]

  connect() {
    this.renumber()
  }

  add() {
    const html = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, Date.now().toString())
    this.listTarget.insertAdjacentHTML("beforeend", html)
    this.renumber()
    const items = this.itemTargets
    const last = items[items.length - 1]
    last.scrollIntoView({ behavior: "smooth", block: "center" })
    last.querySelector("textarea")?.focus()
  }

  remove(event) {
    const item = event.target.closest("[data-nested-form-target='item']")
    const destroy = item.querySelector("[data-nested-form-target='destroy']")
    if (item.querySelector("input[name$='[id]']")) {
      destroy.value = "1"
      item.classList.add("hidden")
    } else {
      item.remove()
    }
    this.renumber()
  }

  renumber() {
    let n = 0
    this.itemTargets.forEach((item) => {
      if (item.classList.contains("hidden")) return
      n += 1
      const num = item.querySelector("[data-nested-form-target='number']")
      const pos = item.querySelector("[data-nested-form-target='position']")
      if (num) num.textContent = n
      if (pos) pos.value = n
    })
  }
}
