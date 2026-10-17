import { Controller } from "@hotwired/stimulus"

// Opens a WhatsApp chat with the message filled in.
// On a computer every chat opens in the same named tab, so WhatsApp Web is reused instead of a
// new tab each time (and without the api.whatsapp.com "Open app / Continue" page in between).
// On a phone it opens the WhatsApp app. Without a saved number it asks for one first.
const TAB = "hireproctor_whatsapp"
const MOBILE = /Android|iPhone|iPad|iPod|Mobile/i

export default class extends Controller {
  static values = { text: String, phone: String }

  open(event) {
    event.preventDefault()
    const digits = this.phoneValue || this.askNumber()
    if (!digits) return

    const query = `phone=${digits}&text=${encodeURIComponent(this.textValue)}`
    if (MOBILE.test(navigator.userAgent)) {
      window.location.href = `https://api.whatsapp.com/send?${query}`
    } else {
      const tab = window.open(`https://web.whatsapp.com/send?${query}`, TAB)
      if (tab) { tab.opener = null; tab.focus() }
    }
  }

  askNumber() {
    const input = window.prompt("WhatsApp number (10 digit mobile):", "")
    if (input === null) return null
    let digits = input.replace(/\D/g, "")
    if (digits.length === 10) digits = `91${digits}`
    if (digits.length < 11) { window.alert("Please enter a valid mobile number."); return null }
    return digits
  }
}
