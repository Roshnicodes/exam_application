import { Controller } from "@hotwired/stimulus"
import { csrfToken } from "lib/media"

// The live practical assessment (Excel / Tally / Word / data entry / coding…):
// countdown, autosave of the typed answer, uploading the solved file(s) and submission.
// Proctoring (camera, screen, warnings) is handled by the proctor controller on the same element.
export default class extends Controller {
  static targets = [ "form", "timer", "clock", "notes", "noteStatus", "fileInput", "fileList", "fileCount", "uploadStatus",
                     "confirm", "confirmFiles", "confirmNote", "submitting", "submittingTitle", "submitButton",
                     "preview", "previewTitle", "previewBody" ]
  static values = {
    secondsLeft: Number, notesUrl: String, filesUrl: String, removeUrl: String,
    requireUpload: Boolean, files: Number, maxFiles: { type: Number, default: 12 }, appSwitch: Boolean
  }

  connect() {
    this.deadline = Date.now() + this.secondsLeftValue * 1000
    this.count = this.filesValue
    this.tick()
    this.timer = setInterval(() => this.tick(), 1000)
    this.refreshSubmit()
  }

  disconnect() {
    clearInterval(this.timer)
    clearTimeout(this.noteTimer)
  }

  // ---------------------------------------------------------------- task file viewer
  // Opens the task file inside this page (not a new tab), so looking at it is never a tab switch.
  async preview(event) {
    const { name, kind, src } = event.currentTarget.dataset
    const body = this.previewBodyTarget
    this.previewTitleTarget.textContent = name
    body.replaceChildren()
    this.previewTarget.classList.remove("hidden")

    if (kind === "sheet" || kind === "doc") {
      body.append(this.previewMessage(kind === "doc" ? "Opening the document…" : "Opening the sheet…"))
      try {
        const response = await fetch(src, { headers: { Accept: "text/html" } })
        if (!response.ok) throw new Error(await response.text())
        body.innerHTML = await response.text()
      } catch (e) {
        body.replaceChildren(this.previewMessage(`This file could not be shown here. ${e.message || ""} Use Download instead.`))
      }
    } else if (kind === "image") {
      const img = document.createElement("img")
      img.src = src
      img.alt = name
      body.append(img)
    } else if (kind === "pdf" || kind === "text") {
      const frame = document.createElement("iframe")
      frame.src = src
      frame.title = name
      body.append(frame)
    } else {
      body.append(this.previewMessage(this.appSwitchValue
        ? "This file type opens in its own app. Download it and open it — switching to that app is allowed for this task."
        : "This file type can't be shown inside the page. Download it to open it in its app — but leaving this page gives a warning, so ask HR (video call / chat) to allow app switching first."))
    }
  }

  showSheet(event) {
    const index = Number(event.currentTarget.dataset.index)
    const sheet = event.currentTarget.closest(".task-sheet")
    sheet.querySelectorAll(".ts-tabs button").forEach((b, i) => b.classList.toggle("active", i === index))
    sheet.querySelectorAll(".ts-sheet").forEach((s, i) => { s.hidden = i !== index })
  }

  closePreview() {
    this.previewTarget.classList.add("hidden")
    this.previewBodyTarget.replaceChildren()
  }

  closePreviewOutside(event) {
    if (event.target === this.previewTarget) this.closePreview()
  }

  previewMessage(text) {
    const p = document.createElement("p")
    p.className = "tp-msg"
    p.textContent = text
    return p
  }

  // ---------------------------------------------------------------- countdown
  tick() {
    const left = Math.max(0, Math.round((this.deadline - Date.now()) / 1000))
    const h = Math.floor(left / 3600)
    const m = String(Math.floor((left % 3600) / 60)).padStart(2, "0")
    const s = String(left % 60).padStart(2, "0")
    this.clockTarget.textContent = h > 0 ? `${h}:${m}:${s}` : `${m}:${s}`
    this.timerTarget.classList.toggle("low", left <= 120)
    if (left === 0) {
      clearInterval(this.timer)
      this.submit("Time is up! Submitting your work…")
    }
  }

  // ---------------------------------------------------------------- typed answer
  notesChanged() {
    clearTimeout(this.noteTimer)
    this.setNoteStatus("Saving…")
    this.noteTimer = setTimeout(() => this.saveNotes(), 900)
  }

  async saveNotes() {
    if (!this.hasNotesTarget) return
    try {
      const res = await fetch(this.notesUrlValue, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": csrfToken() },
        body: JSON.stringify({ notes: this.notesTarget.value })
      })
      if (!res.ok) throw new Error(res.status)
      const data = await res.json()
      if (typeof data.seconds_left === "number") this.deadline = Date.now() + data.seconds_left * 1000
      this.setNoteStatus("Saved ✓")
      this.refreshSubmit()
    } catch (e) {
      this.setNoteStatus("Not saved — check your internet")
    }
  }

  setNoteStatus(text) {
    if (this.hasNoteStatusTarget) this.noteStatusTarget.textContent = text
  }

  // ---------------------------------------------------------------- uploads
  pick() {
    this.fileInputTarget.click()
  }

  dragOver(event) {
    event.preventDefault()
    event.currentTarget.classList.add("drag")
  }

  dragLeave(event) {
    event.currentTarget.classList.remove("drag")
  }

  dropped(event) {
    event.preventDefault()
    event.currentTarget.classList.remove("drag")
    if (event.dataTransfer.files.length) this.upload(event.dataTransfer.files)
  }

  chosen(event) {
    if (event.target.files.length) this.upload(event.target.files)
  }

  async upload(files) {
    if (this.uploading) return
    this.uploading = true
    const body = new FormData()
    Array.from(files).forEach((f) => body.append("files[]", f))
    this.setUploadStatus(`Uploading ${files.length} file${files.length === 1 ? "" : "s"}…`, "busy")
    try {
      const res = await fetch(this.filesUrlValue, { method: "POST", headers: { "X-CSRF-Token": csrfToken(), "Accept": "application/json" }, body })
      const data = await res.json()
      if (data.files) this.renderFiles(data.files)
      this.setUploadStatus(data.error || "Uploaded ✓ — HR has your file", data.error ? "bad" : "ok")
    } catch (e) {
      this.setUploadStatus("Upload failed. Check your internet and try again.", "bad")
    } finally {
      this.uploading = false
      this.fileInputTarget.value = ""
    }
  }

  async remove(event) {
    const id = event.currentTarget.dataset.fileId
    if (!id || !window.confirm("Remove this file? You can upload it again.")) return
    try {
      const res = await fetch(this.removeUrlValue.replace("__ID__", id), {
        method: "DELETE", headers: { "X-CSRF-Token": csrfToken(), "Accept": "application/json" }
      })
      const data = await res.json()
      if (data.files) this.renderFiles(data.files)
      this.setUploadStatus("File removed.", "")
    } catch (e) {
      this.setUploadStatus("Could not remove the file.", "bad")
    }
  }

  renderFiles(files) {
    this.count = files.length
    const safe = (t) => String(t).replace(/[<>&"]/g, (c) => ({ "<": "&lt;", ">": "&gt;", "&": "&amp;", '"': "&quot;" }[c]))
    this.fileListTarget.innerHTML = files.length
      ? files.map((f) => `
          <div class="file-row">
            <span class="file-ico">📄</span>
            <div class="grow"><b>${safe(f.name)}</b><span class="tiny muted">${(f.size / 1024).toFixed(0)} KB · uploaded ${safe(f.at)}</span></div>
            <button type="button" class="btn btn-light btn-sm" data-action="assessment#remove" data-file-id="${f.id}">Remove</button>
          </div>`).join("")
      : `<p class="small muted">No file uploaded yet.</p>`
    if (this.hasFileCountTarget) this.fileCountTarget.textContent = files.length
    this.refreshSubmit()
  }

  setUploadStatus(text, state) {
    if (!this.hasUploadStatusTarget) return
    this.uploadStatusTarget.textContent = text
    this.uploadStatusTarget.className = `upload-status ${state || ""}`
  }

  // The submit button stays off until there is something to submit.
  refreshSubmit() {
    const typed = this.hasNotesTarget && this.notesTarget.value.trim().length > 0
    this.ready = !this.requireUploadValue || this.count > 0 || typed
    this.submitButtonTargets.forEach((button) => {
      button.disabled = !this.ready
      button.title = this.ready ? "" : "Upload your solved file first"
    })
  }

  // ---------------------------------------------------------------- submission
  confirmSubmit() {
    if (this.hasNotesTarget) this.saveNotes()
    if (this.hasConfirmFilesTarget) {
      this.confirmFilesTarget.textContent = this.count === 0 ? "No file uploaded" : `${this.count} file${this.count === 1 ? "" : "s"} uploaded`
    }
    if (this.hasConfirmNoteTarget) {
      this.confirmNoteTarget.classList.toggle("hidden", this.count > 0)
    }
    this.confirmTarget.classList.remove("hidden")
  }

  cancelSubmit() {
    this.confirmTarget.classList.add("hidden")
  }

  async submit(title) {
    if (this.submitted) return
    this.submitted = true
    clearInterval(this.timer)
    this.confirmTarget.classList.add("hidden")
    if (typeof title === "string") this.submittingTitleTarget.textContent = title
    this.submittingTarget.classList.remove("hidden")
    if (this.hasNotesTarget) await this.saveNotes()

    const waits = []
    this.dispatch("before-submit", { detail: { waits } })
    await Promise.race([ Promise.allSettled(waits), new Promise((r) => setTimeout(r, 20000)) ])
    this.formTarget.submit()
  }

  // The server ended the assessment (warning limit / HR). Files and notes are already saved.
  async forceSubmit(event) {
    if (this.submitted) return
    this.submitted = true
    clearInterval(this.timer)
    this.submittingTitleTarget.textContent = "Assessment ended"
    this.submittingTarget.classList.remove("hidden")
    const waits = []
    this.dispatch("before-submit", { detail: { waits } })
    await Promise.race([ Promise.allSettled(waits), new Promise((r) => setTimeout(r, 15000)) ])
    window.location.replace(event.detail.redirect || window.location.href)
  }
}
