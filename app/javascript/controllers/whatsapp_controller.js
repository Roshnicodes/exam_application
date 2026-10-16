import { Controller } from "@hotwired/stimulus"

// WhatsApp button for someone without a saved number: asks for it, then opens their chat.
export default class extends Controller {
  static values = { text: String }

  open() {
    const input = window.prompt("WhatsApp number (10 digit mobile):", "")
    if (input === null) return
    let digits = input.replace(/\D/g, "")
    if (digits.length === 10) digits = `91${digits}`
    if (digits.length < 11) return window.alert("Please enter a valid mobile number.")
    window.open(`https://api.whatsapp.com/send?phone=${digits}&text=${encodeURIComponent(this.textValue)}`, "_blank", "noopener")
  }
}
