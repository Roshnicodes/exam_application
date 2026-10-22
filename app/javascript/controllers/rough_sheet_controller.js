import { Controller } from "@hotwired/stimulus"
import { csrfToken } from "lib/media"

// Digital rough sheet in the test: write with the mouse / finger / stylus like on a copy, or type.
// Saved automatically (and once more on submit) so HR can see the rough work.
export default class extends Controller {
  static targets = [ "panel", "canvas", "wrap", "notes", "writeTab", "typeTab", "writePane", "typePane", "status", "penBtn", "eraserBtn" ]
  static values = { url: String, image: String }

  connect() {
    this.tool = "pen"
    this.undoStack = []
    this.height = 1100
    this.setupCanvas()
    if (this.imageValue) this.restore(this.imageValue)
  }

  disconnect() {
    clearTimeout(this.saveTimer)
  }

  // ---- open / close -------------------------------------------------------
  toggle() {
    const open = this.panelTarget.classList.toggle("open")
    document.body.classList.toggle("rough-open", open)
    if (open) this.resizeToPanel()
  }

  close() {
    this.panelTarget.classList.remove("open")
    document.body.classList.remove("rough-open")
  }

  showWrite() { this.switchTab(true) }
  showType() { this.switchTab(false) }

  switchTab(write) {
    this.writeTabTarget.classList.toggle("active", write)
    this.typeTabTarget.classList.toggle("active", !write)
    this.writePaneTarget.hidden = !write
    this.typePaneTarget.hidden = write
    if (!write) this.notesTarget.focus()
  }

  // ---- canvas -------------------------------------------------------------
  setupCanvas() {
    this.ratio = window.devicePixelRatio || 1
    this.width = 500
    this.sizeCanvas(this.width, this.height)
    const c = this.canvasTarget
    c.addEventListener("pointerdown", (e) => this.start(e))
    c.addEventListener("pointermove", (e) => this.move(e))
    ;[ "pointerup", "pointercancel", "pointerleave" ].forEach((t) => c.addEventListener(t, () => this.end()))
  }

  // the canvas follows the panel's width (phones) without losing what's written
  resizeToPanel() {
    const w = Math.round(this.wrapTarget.clientWidth - 2)
    if (w > 200 && Math.abs(w - this.width) > 4) this.sizeCanvas(w, this.height, true)
  }

  sizeCanvas(w, h, keep = false) {
    const c = this.canvasTarget
    const old = keep ? this.snapshotCanvas() : null
    this.width = w
    this.height = h
    c.width = Math.round(w * this.ratio)
    c.height = Math.round(h * this.ratio)
    c.style.width = `${w}px`
    c.style.height = `${h}px`
    this.ctx = c.getContext("2d")
    this.ctx.scale(this.ratio, this.ratio)
    this.ctx.lineCap = "round"
    this.ctx.lineJoin = "round"
    if (old) this.ctx.drawImage(old, 0, 0, old.width / this.ratio, old.height / this.ratio)
  }

  snapshotCanvas() {
    const copy = document.createElement("canvas")
    copy.width = this.canvasTarget.width
    copy.height = this.canvasTarget.height
    copy.getContext("2d").drawImage(this.canvasTarget, 0, 0)
    return copy
  }

  point(e) {
    const r = this.canvasTarget.getBoundingClientRect()
    return { x: e.clientX - r.left, y: e.clientY - r.top }
  }

  start(e) {
    e.preventDefault()
    this.canvasTarget.setPointerCapture?.(e.pointerId)
    this.undoStack.push(this.ctx.getImageData(0, 0, this.canvasTarget.width, this.canvasTarget.height))
    if (this.undoStack.length > 15) this.undoStack.shift()
    this.drawing = true
    this.last = this.point(e)
    const eraser = this.tool === "eraser"
    this.ctx.globalCompositeOperation = eraser ? "destination-out" : "source-over"
    this.ctx.strokeStyle = "#1e293b"
    this.ctx.lineWidth = eraser ? 22 : (e.pointerType === "pen" ? 1.6 + (e.pressure || 0.5) * 1.6 : 2.4)
    this.ctx.beginPath()
    this.ctx.arc(this.last.x, this.last.y, this.ctx.lineWidth / 2, 0, Math.PI * 2)
    this.ctx.fillStyle = "#1e293b"
    this.ctx.fill()
  }

  move(e) {
    if (!this.drawing) return
    const p = this.point(e)
    const mid = { x: (this.last.x + p.x) / 2, y: (this.last.y + p.y) / 2 }
    this.ctx.beginPath()
    this.ctx.moveTo(this.lastMid?.x ?? this.last.x, this.lastMid?.y ?? this.last.y)
    this.ctx.quadraticCurveTo(this.last.x, this.last.y, mid.x, mid.y)
    this.ctx.stroke()
    this.last = p
    this.lastMid = mid
  }

  end() {
    if (!this.drawing) return
    this.drawing = false
    this.lastMid = null
    this.ctx.globalCompositeOperation = "source-over"
    this.changed()
  }

  pen() { this.setTool("pen") }
  eraser() { this.setTool("eraser") }

  setTool(tool) {
    this.tool = tool
    this.penBtnTarget.classList.toggle("active", tool === "pen")
    this.eraserBtnTarget.classList.toggle("active", tool === "eraser")
    this.canvasTarget.classList.toggle("erasing", tool === "eraser")
  }

  undo() {
    const data = this.undoStack.pop()
    if (!data) return
    this.ctx.putImageData(data, 0, 0)
    this.changed()
  }

  clear() {
    if (!window.confirm("Clear the whole rough sheet?")) return
    this.undoStack.push(this.ctx.getImageData(0, 0, this.canvasTarget.width, this.canvasTarget.height))
    this.ctx.clearRect(0, 0, this.width, this.height)
    this.changed()
  }

  moreSpace() {
    this.sizeCanvas(this.width, this.height + 700, true)
    this.wrapTarget.scrollTo({ top: this.wrapTarget.scrollHeight, behavior: "smooth" })
  }

  // a sheet saved earlier (page reopened): draw it back
  restore(url) {
    const img = new Image()
    img.onload = () => {
      const h = img.height / this.ratio
      if (h > this.height) this.sizeCanvas(this.width, h)
      this.ctx.drawImage(img, 0, 0, img.width / this.ratio, img.height / this.ratio)
    }
    img.src = url
  }

  // ---- saving -------------------------------------------------------------
  changed() {
    this.dirty = true
    this.scheduleSave()
  }

  notesChanged() {
    this.notesDirty = true
    this.scheduleSave()
  }

  scheduleSave() {
    this.setStatus("Saving…")
    clearTimeout(this.saveTimer)
    this.saveTimer = setTimeout(() => this.save(), 2500)
  }

  async save() {
    clearTimeout(this.saveTimer)
    if (!this.dirty && !this.notesDirty) return
    const form = new FormData()
    if (this.notesDirty) form.append("notes", this.notesTarget.value)
    if (this.dirty) {
      const blob = await this.exportPng()
      if (blob) form.append("sheet", blob, "rough-sheet.png")
    }
    this.dirty = this.notesDirty = false
    try {
      const res = await fetch(this.urlValue, { method: "PATCH", headers: { "X-CSRF-Token": csrfToken() }, body: form })
      this.setStatus(res.ok ? "Saved ✓" : "Not saved — will retry")
      if (!res.ok) this.dirty = this.notesDirty = true
    } catch {
      this.dirty = this.notesDirty = true
      this.setStatus("Offline — will retry")
    }
  }

  // white background so the saved page looks like paper
  exportPng() {
    const out = document.createElement("canvas")
    out.width = this.canvasTarget.width
    out.height = this.canvasTarget.height
    const ctx = out.getContext("2d")
    ctx.fillStyle = "#fff"
    ctx.fillRect(0, 0, out.width, out.height)
    ctx.drawImage(this.canvasTarget, 0, 0)
    return new Promise((resolve) => out.toBlob(resolve, "image/png"))
  }

  // the exam is being submitted: save one last time
  flush(event) {
    event.detail?.waits?.push(this.save())
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
