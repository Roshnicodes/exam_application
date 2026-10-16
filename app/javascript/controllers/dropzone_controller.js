import { Controller } from "@hotwired/stimulus"

// Pretty file picker with drag & drop and selected file name.
export default class extends Controller {
  static targets = [ "input", "label" ]
  static values = { submit: Boolean }

  connect() {
    this.default = this.labelTarget.innerHTML
    ;[ "dragenter", "dragover" ].forEach((t) => this.element.addEventListener(t, (e) => { e.preventDefault(); this.element.classList.add("drag") }))
    ;[ "dragleave", "drop" ].forEach((t) => this.element.addEventListener(t, () => this.element.classList.remove("drag")))
    this.element.addEventListener("drop", (e) => {
      e.preventDefault()
      if (!e.dataTransfer.files.length) return
      this.inputTarget.files = e.dataTransfer.files
      this.changed()
    })
  }

  pick() {
    this.inputTarget.click()
  }

  changed() {
    const file = this.inputTarget.files[0]
    this.element.classList.toggle("filled", !!file)
    this.labelTarget.innerHTML = file ? `<b>${file.name.replace(/[<>&]/g, "")}</b> · ${(file.size / 1024).toFixed(1)} KB` : this.default
    if (file && this.submitValue) this.inputTarget.form.requestSubmit()
  }
}
