import { Controller } from "@hotwired/stimulus"

// Single OTP field: keeps digits only and submits automatically once 6 digits are entered.
export default class extends Controller {
  static targets = [ "field", "submit" ]

  connect() {
    this.fieldTarget.focus()
    this.input()
  }

  input() {
    const digits = this.fieldTarget.value.replace(/\D/g, "").slice(0, 6)
    if (this.fieldTarget.value !== digits) this.fieldTarget.value = digits
    this.submitTarget.disabled = digits.length !== 6
    if (digits.length === 6 && !this.submitted) {
      this.submitted = true
      this.element.requestSubmit()
    }
  }
}
