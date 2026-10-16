import { Controller } from "@hotwired/stimulus"

const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c])

// Searchable dropdown on top of a native <select> (single or multiple).
// The native select stays in the form, so submission works exactly as before.
export default class extends Controller {
  static targets = [ "select" ]
  static values = { placeholder: { type: String, default: "Search…" } }

  connect() {
    this.select = this.selectTarget
    this.multiple = this.select.multiple
    this.select.classList.add("combo-native")
    this.select.tabIndex = -1

    this.root = document.createElement("div")
    this.root.className = "combo"
    this.root.innerHTML = `
      <div class="combo-control">
        <div class="combo-chips"></div>
        <input type="text" class="combo-input" autocomplete="off" placeholder="${esc(this.placeholderValue)}">
        <svg class="icon combo-caret" viewBox="0 0 24 24"><path d="m6 9 6 6 6-6"/></svg>
      </div>
      <div class="combo-menu hidden" role="listbox"></div>`
    this.select.after(this.root)
    this.chips = this.root.querySelector(".combo-chips")
    this.input = this.root.querySelector(".combo-input")
    this.menu = this.root.querySelector(".combo-menu")

    this.root.querySelector(".combo-control").addEventListener("mousedown", (e) => {
      if (e.target.closest(".chip-x")) return
      if (e.target !== this.input) e.preventDefault()
      this.input.focus()
      this.open()
    })
    this.input.addEventListener("input", () => { this.active = 0; this.open() })
    this.input.addEventListener("keydown", (e) => this.keydown(e))
    this.input.addEventListener("blur", () => setTimeout(() => this.close(), 150))
    this.menu.addEventListener("mousedown", (e) => {
      const item = e.target.closest("[data-value]")
      if (!item) return
      e.preventDefault()
      this.choose(item.dataset.value)
    })
    this.chips.addEventListener("click", (e) => {
      const x = e.target.closest(".chip-x")
      if (x) this.toggle(x.dataset.value, false)
    })
    this.render()
  }

  disconnect() {
    this.root?.remove()
    this.select.classList.remove("combo-native")
  }

  get options() {
    return [ ...this.select.options ].filter((o) => o.value !== "")
  }

  open() {
    const q = this.input.value.trim().toLowerCase()
    const matches = this.options.filter((o) => {
      const hay = `${o.text} ${o.dataset.sub || ""} ${o.parentElement.label || ""}`.toLowerCase()
      return !q || q.split(/\s+/).every((w) => hay.includes(w))
    })
    this.matches = matches.slice(0, 80)
    this.active = Math.min(this.active || 0, Math.max(this.matches.length - 1, 0))
    this.menu.innerHTML = this.matches.length
      ? this.matches.map((o, i) => `
          <div class="combo-item ${o.selected ? "selected" : ""} ${i === this.active ? "active" : ""}" data-value="${esc(o.value)}" role="option">
            <span class="avatar soft">${esc(o.text.split(/\s+/).map((w) => w[0]).slice(0, 2).join("").toUpperCase())}</span>
            <span class="grow"><b>${esc(o.text)}</b>${o.dataset.sub || o.parentElement.label ? `<small>${esc(o.dataset.sub || o.parentElement.label)}</small>` : ""}</span>
            ${o.selected ? '<svg class="icon" viewBox="0 0 24 24"><path d="M20 6 9 17l-5-5"/></svg>' : ""}
          </div>`).join("") + (matches.length > 80 ? `<div class="combo-empty">${matches.length - 80} more — keep typing to narrow down</div>` : "")
      : `<div class="combo-empty">No match for “${esc(this.input.value)}”</div>`
    this.menu.classList.remove("hidden")
    this.root.classList.add("open")
  }

  close() {
    this.menu.classList.add("hidden")
    this.root.classList.remove("open")
    if (!this.multiple) this.input.value = ""
    this.renderInput()
  }

  keydown(e) {
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault()
      if (this.menu.classList.contains("hidden")) return this.open()
      const n = this.matches.length
      this.active = (this.active + (e.key === "ArrowDown" ? 1 : -1) + n) % n
      this.open()
      this.menu.querySelector(".active")?.scrollIntoView({ block: "nearest" })
    } else if (e.key === "Enter") {
      if (this.menu.classList.contains("hidden")) return
      e.preventDefault()
      const o = this.matches?.[this.active]
      if (o) this.choose(o.value)
    } else if (e.key === "Escape") {
      this.close()
    } else if (e.key === "Backspace" && !this.input.value && this.multiple) {
      const last = this.options.filter((o) => o.selected).pop()
      if (last) this.toggle(last.value, false)
    }
  }

  choose(value) {
    if (this.multiple) {
      const o = this.options.find((x) => x.value === value)
      this.toggle(value, !o.selected)
      this.input.value = ""
      this.open()
    } else {
      this.select.value = value
      this.select.dispatchEvent(new Event("change", { bubbles: true }))
      this.input.value = ""
      this.render()
      this.input.blur()
    }
  }

  toggle(value, on) {
    const o = this.options.find((x) => x.value === value)
    if (o) o.selected = on
    this.select.dispatchEvent(new Event("change", { bubbles: true }))
    this.render()
    if (!this.menu.classList.contains("hidden")) this.open()
  }

  render() {
    if (this.multiple) {
      const chosen = this.options.filter((o) => o.selected)
      this.chips.innerHTML = chosen.map((o) => `
        <span class="combo-chip">${esc(o.text)}<button type="button" class="chip-x" data-value="${esc(o.value)}" aria-label="Remove ${esc(o.text)}">×</button></span>`).join("")
      this.root.classList.toggle("has-value", chosen.length > 0)
    }
    this.renderInput()
  }

  renderInput() {
    if (this.multiple) {
      this.input.placeholder = this.options.some((o) => o.selected) ? "Add more…" : this.placeholderValue
    } else {
      const o = this.select.selectedOptions[0]
      this.input.placeholder = o && o.value ? o.text : this.placeholderValue
      this.root.classList.toggle("has-value", !!(o && o.value))
    }
  }
}
