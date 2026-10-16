import { Controller } from "@hotwired/stimulus"

// Add / remove simple rows (selection parameters, batch candidates),
// keep a running weightage total / row count, and turn pasted Excel rows into rows.
export default class extends Controller {
  static targets = [ "list", "template", "total", "count", "paste" ]

  connect() {
    this.update()
    this.element.addEventListener("input", () => this.update())
  }

  add() {
    this.listTarget.insertAdjacentHTML("beforeend", this.templateTarget.innerHTML)
    this.listTarget.lastElementChild.querySelector("input")?.focus()
    this.update()
  }

  remove(e) {
    e.target.closest(".repeat-row").remove()
    this.update()
  }

  // Each pasted line becomes a row; cells split on tabs (Excel) or commas.
  paste() {
    const lines = this.pasteTarget.value.split(/\r?\n/).map((l) => l.trim()).filter(Boolean)
    lines.forEach((line) => {
      const cells = line.split(line.includes("\t") ? "\t" : ",").map((c) => c.trim())
      if (/^name$/i.test(cells[0])) return // skip a copied header row
      let row = [ ...this.listTarget.children ].find((r) => [ ...r.querySelectorAll("input") ].every((i) => !i.value))
      if (!row) {
        this.listTarget.insertAdjacentHTML("beforeend", this.templateTarget.innerHTML)
        row = this.listTarget.lastElementChild
      }
      row.querySelectorAll("input").forEach((input, i) => { input.value = cells[i] || "" })
    })
    this.pasteTarget.value = ""
    this.update()
  }

  update() {
    if (this.hasTotalTarget) {
      const total = [ ...this.listTarget.querySelectorAll("input[type=number]") ].reduce((s, i) => s + (Number(i.value) || 0), 0)
      this.totalTarget.textContent = `${total}%`
      this.totalTarget.classList.toggle("bad", total !== 100 && total !== 0)
    }
    if (this.hasCountTarget) {
      const rows = [ ...this.listTarget.children ]
      rows.forEach((r, i) => { const n = r.querySelector(".row-num"); if (n) n.textContent = i + 1 })
      const filled = rows.filter((r) => r.querySelector("input")?.value.trim()).length
      this.countTarget.textContent = `${filled} candidate${filled === 1 ? "" : "s"}`
    }
  }
}
