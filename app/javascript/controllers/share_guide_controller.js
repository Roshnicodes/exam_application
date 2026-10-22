import { Controller } from "@hotwired/stimulus"

// "Share + PDF": shares the invitation message together with the candidate guide PDF through the
// device's share menu (WhatsApp, Gmail, Telegram…). Where a browser can't share files (e.g. Linux),
// it downloads the PDF and opens WhatsApp with the message, so the PDF can be attached there.
export default class extends Controller {
  static values = { text: String, pdf: String, filename: String, whatsapp: String }

  async share() {
    try {
      const blob = await (await fetch(this.pdfValue)).blob()
      const file = new File([ blob ], this.filenameValue, { type: "application/pdf" })
      if (navigator.canShare?.({ files: [ file ] })) {
        await navigator.share({ text: this.textValue, files: [ file ], title: this.filenameValue })
        return
      }
      this.download(blob)
    } catch (e) {
      if (e?.name === "AbortError") return // closed the share menu
      this.download(null)
    }
    if (this.whatsappValue) window.open(this.whatsappValue, "hireproctor_whatsapp")
    window.alert("This browser can't attach files directly. The guide PDF has been downloaded — attach it in WhatsApp / email (📎) with the message.")
  }

  download(blob) {
    const a = document.createElement("a")
    a.href = blob ? URL.createObjectURL(blob) : this.pdfValue
    a.download = this.filenameValue
    document.body.append(a)
    a.click()
    a.remove()
  }
}
