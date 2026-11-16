import { Controller } from "@hotwired/stimulus"
import { csrfToken } from "lib/media"
import { Workbook, loadFunctions, shiftFormula, adjustReferences, formatValue, literal, colName, colIndex, address, isError, formatNumber, COMMON_FUNCTIONS } from "lib/formula"

const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c])
const MAX_ROWS = 1000
const MAX_COLS = 52
const DEFAULT_WIDTH = 72
const PALETTE = [ "#000000", "#ffffff", "#e7e6e6", "#44546a", "#4472c4", "#ed7d31", "#a5a5a5", "#ffc000", "#5b9bd5", "#70ad47",
                  "#7f7f7f", "#f2f2f2", "#d0cece", "#d6dce4", "#d9e1f2", "#fce4d6", "#ededed", "#fff2cc", "#ddebf7", "#e2efda",
                  "#c00000", "#ff0000", "#ffc000", "#ffff00", "#92d050", "#00b050", "#00b0f0", "#0070c0", "#002060", "#7030a0" ]

// The built-in spreadsheet of a practical Excel assessment — looks and works like Excel:
// ribbon (fonts, fills, alignment, number formats, insert / delete, AutoSum, sort), formula bar,
// fill handle, column resizing, right-click menu, sheet tabs, status bar with Sum / Average / Count.
// Everything stays on the proctored page; it saves by itself and becomes an .xlsx for HR.
export default class extends Controller {
  static targets = [ "grid", "wrap", "name", "formula", "tabs", "status", "title", "help", "stats", "zoomLabel", "menu", "palette", "fontSize", "numberFormat", "mode", "ribbon" ]
  static values = { url: String, saveUrl: String }

  async connect() {
    this.sheet = 0
    this.sel = { r: 0, c: 0, r2: 0, c2: 0 }
    this.undoStack = []
    this.redoStack = []
    this.clip = null
    this.zoom = 1
    this.setStatus("Loading…")
    const [ data, fns ] = await Promise.all([ this.load(), loadFunctions() ])
    if (!data) return
    const sheets = data.sheets.map((s) => ({
      name: String(s.name || "Sheet"),
      cells: (s.cells || []).map((row) => (row || []).map((v) => String(v ?? ""))),
      styles: s.styles && typeof s.styles === "object" ? s.styles : {},
      widths: s.widths && typeof s.widths === "object" ? s.widths : {}
    }))
    this.book = new Workbook(sheets, fns)
    this.renderTabs()
    this.render()
    this.setStatus(data.saved_at ? "Saved" : "Saved")

    // Keyboard "catcher": a hidden text box sitting on the active cell. Typing there — from a
    // keyboard, a phone keyboard, Hindi / IME input or text inserted by the system — starts
    // editing the cell, like Excel.
    this.catcher = document.createElement("textarea")
    this.catcher.className = "sx-catch"
    this.catcher.setAttribute("aria-label", "Spreadsheet cell")
    this.catcher.spellcheck = false
    this.catcher.autocapitalize = "off"
    this.wrapTarget.appendChild(this.catcher)
    this.onKey = (e) => this.keydown(e)
    this.catcher.addEventListener("keydown", this.onKey)
    this.gridTarget.addEventListener("keydown", this.onKey)
    const takeTyped = () => {
      const text = this.catcher.value
      this.catcher.value = ""
      if (text && !this.editing) this.startEdit(text)
    }
    this.catcher.addEventListener("input", (e) => { if (!e.isComposing) takeTyped() })
    this.catcher.addEventListener("compositionend", takeTyped) // Hindi / IME: the finished word
    this.onUp = (e) => this.mouseup(e)
    window.addEventListener("pointerup", this.onUp) // mouse, touch and pen
    this.onMove = (e) => this.mousemove(e)
    window.addEventListener("pointermove", this.onMove)
    this.onDocDown = (e) => { if (!e.target.closest(".sx-menu, .sx-palette, [data-palette]")) this.closeMenus() }
    document.addEventListener("mousedown", this.onDocDown)
    this.submitHook = (e) => e.detail?.waits?.push(this.save())
    this.element.closest("[data-controller~='assessment']")?.addEventListener("assessment:before-submit", this.submitHook)
    this.saveTimer = setInterval(() => { if (this.dirty) this.save() }, 15000)
    this.focusGrid()
  }

  disconnect() {
    document.querySelector(".sx-backdrop")?.remove()
    document.body.classList.remove("sx-open")
    clearInterval(this.saveTimer)
    clearTimeout(this.debounce)
    window.removeEventListener("pointerup", this.onUp)
    window.removeEventListener("pointermove", this.onMove)
    document.removeEventListener("mousedown", this.onDocDown)
    this.element.closest("[data-controller~='assessment']")?.removeEventListener("assessment:before-submit", this.submitHook)
  }

  async load() {
    try {
      const res = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      const data = await res.json()
      if (!res.ok || !data.sheets?.length) throw new Error(data.error || "empty")
      return data
    } catch (e) {
      this.setStatus(`Couldn't open the task sheet (${e.message}). Reload the page or ask HR.`, true)
      return null
    }
  }

  // ================================================================ data helpers
  get current() { return this.book.sheets[this.sheet] }
  get cells() { return this.current.cells }
  raw(r, c, s = this.sheet) { return this.book.sheets[s].cells[r]?.[c] ?? "" }
  styleOf(r, c, s = this.sheet) { return this.book.sheets[s].styles[`${r}:${c}`] || {} }
  value(r, c) { return this.book.value(this.sheet, r, c) }
  width(c) { return Number(this.current.widths[c]) || DEFAULT_WIDTH }

  display(r, c) {
    const v = this.value(r, c)
    if (v === null || v === undefined) return ""
    if (isError(v)) return v.code || v.message
    if (typeof v === "number") return formatValue(v, this.styleOf(r, c)) ?? formatNumber(v)
    if (typeof v === "boolean") return v ? "TRUE" : "FALSE"
    return String(v)
  }

  // Before every change: a copy of the workbook for Undo
  snapshot() {
    this.undoStack.push(JSON.stringify(this.book.sheets))
    if (this.undoStack.length > 60) this.undoStack.shift()
    this.redoStack = []
  }

  restore(json) {
    const sheets = JSON.parse(json)
    sheets.forEach((s, i) => { this.book.sheets[i] = s })
    this.book.sheets.length = sheets.length
    if (this.sheet >= sheets.length) this.sheet = 0
    this.afterChange(true)
    this.renderTabs()
  }

  undo() {
    if (!this.undoStack.length) return
    this.redoStack.push(JSON.stringify(this.book.sheets))
    this.restore(this.undoStack.pop())
  }

  redo() {
    if (!this.redoStack.length) return
    this.undoStack.push(JSON.stringify(this.book.sheets))
    this.restore(this.redoStack.pop())
  }

  put(r, c, v, s = this.sheet) {
    const cells = this.book.sheets[s].cells
    while (cells.length <= r) cells.push([])
    while (cells[r].length <= c) cells[r].push("")
    cells[r][c] = String(v ?? "")
  }

  trim() {
    this.book.sheets.forEach((s) => {
      s.cells.forEach((row) => { while (row.length && row[row.length - 1] === "") row.pop() })
      while (s.cells.length && s.cells[s.cells.length - 1].length === 0) s.cells.pop()
    })
  }

  afterChange(full = false) {
    this.trim()
    this.book.invalidate()
    this.book.parsed = new Map()
    if (full || this.needsGrow()) this.render()
    else this.refreshValues()
    this.changed()
  }

  needsGrow() {
    const rows = this.cells.length, cols = this.cells.reduce((m, row) => Math.max(m, row.length), 0)
    return rows > this.rows - 5 || cols > this.cols - 2
  }

  // ================================================================ drawing
  size() {
    const usedCols = this.cells.reduce((m, row) => Math.max(m, row.length), 0)
    const styled = Object.keys(this.current.styles).map((k) => k.split(":").map(Number))
    const maxR = Math.max(this.cells.length, ...styled.map(([ r ]) => r + 1), 0)
    const maxC = Math.max(usedCols, ...styled.map(([ , c ]) => c + 1), 0)
    this.rows = Math.min(MAX_ROWS, Math.max(this.minRows?.[this.sheet] || 0, maxR + 20, 40))
    this.cols = Math.min(MAX_COLS, Math.max(maxC + 4, 14))
  }

  render() {
    this.size()
    // first time on a sheet: columns as wide as their content (like opening the file in Excel)
    if (!this.current.autoWidths) {
      this.current.autoWidths = true
      for (let c = 0; c < this.cols; c++) {
        if (this.current.widths[c]) continue
        let w = 0
        for (let r = 0; r < Math.min(this.cells.length, 300); r++) {
          if (this.styleOf(r, c).w) continue
          const next = this.raw(r, c + 1)
          const text = this.display(r, c)
          if (next === "" && typeof this.value(r, c) === "string" && text.length > 14) continue // long text spills over
          w = Math.max(w, text.length)
        }
        const cap = Math.max(120, Math.min(320, (this.wrapTarget.clientWidth || 800) - 70))
        if (w > 8) this.current.widths[c] = Math.min(Math.round(w * 7.4 + 14), cap)
      }
    }
    const cols = Array.from({ length: this.cols }, (_, c) => `<col style="width:${this.width(c)}px">`).join("")
    let html = `<colgroup><col style="width:44px">${cols}</colgroup><thead><tr><th class="sx-corner" data-action="click->sheet-editor#selectAll"></th>`
    for (let c = 0; c < this.cols; c++) html += `<th data-col="${c}">${colName(c)}<span class="sx-resize" data-resize="${c}"></span></th>`
    html += "</tr></thead><tbody>"
    for (let r = 0; r < this.rows; r++) {
      html += `<tr><th data-row="${r}">${r + 1}</th>`
      for (let c = 0; c < this.cols; c++) html += this.cellHtml(r, c)
      html += "</tr>"
    }
    this.gridTarget.innerHTML = html + "</tbody>"
    this.gridTarget.style.setProperty("--sx-zoom", this.zoom)
    this.paintSelection()
  }

  cellHtml(r, c) {
    const { cls, style, title, text } = this.cellParts(r, c)
    return `<td data-r="${r}" data-c="${c}" class="${cls}" style="${style}"${title ? ` title="${esc(title)}"` : ""}>${text ? `<span>${esc(text)}</span>` : ""}</td>`
  }

  cellParts(r, c) {
    const raw = this.raw(r, c)
    const v = this.value(r, c)
    const st = this.styleOf(r, c)
    const css = []
    if (st.b) css.push("font-weight:700")
    if (st.i) css.push("font-style:italic")
    if (st.u) css.push("text-decoration:underline")
    if (st.fc) css.push(`color:${st.fc}`)
    if (st.bg) css.push(`background:${st.bg}`)
    if (st.fs) css.push(`font-size:calc(${st.fs}px * var(--sx-zoom, 1))`)
    const align = st.al || (typeof v === "number" ? "right" : typeof v === "boolean" || isError(v) ? "center" : "left")
    css.push(`text-align:${align}`)
    const text = this.display(r, c)
    const cls = []
    if (isError(v)) cls.push("err")
    if (st.w) cls.push("wrap")
    // text spills into the empty cells on its right, like Excel
    else if (text && typeof v === "string" && align === "left" && this.raw(r, c + 1) === "") cls.push("spill")
    return { cls: cls.join(" "), style: css.join(";"), title: raw.startsWith("=") ? raw : "", text }
  }

  refreshValues() {
    this.book.invalidate()
    this.gridTarget.querySelectorAll("td").forEach((td) => {
      const { cls, style, title, text } = this.cellParts(+td.dataset.r, +td.dataset.c)
      td.className = cls
      td.setAttribute("style", style)
      if (title) td.title = title; else td.removeAttribute("title")
      td.innerHTML = text ? `<span>${esc(text)}</span>` : ""
    })
    this.paintSelection()
  }

  renderTabs() {
    this.tabsTarget.innerHTML = this.book.sheets.map((s, i) =>
      `<button type="button" class="${i === this.sheet ? "active" : ""}" data-index="${i}" data-action="sheet-editor#switchSheet">${esc(s.name)}</button>`).join("") +
      `<button type="button" class="sx-add" title="New sheet" data-action="sheet-editor#addSheet">+</button>`
  }

  switchSheet(event) {
    this.commitEdit()
    this.sheet = +event.currentTarget.dataset.index
    this.sel = { r: 0, c: 0, r2: 0, c2: 0 }
    this.renderTabs()
    this.render()
    this.focusGrid()
  }

  addSheet() {
    this.commitEdit()
    this.snapshot()
    let n = this.book.sheets.length + 1
    while (this.book.sheets.some((s) => s.name.toLowerCase() === `sheet${n}`)) n++
    this.book.sheets.push({ name: `Sheet${n}`, cells: [], styles: {}, widths: {} })
    this.sheet = this.book.sheets.length - 1
    this.sel = { r: 0, c: 0, r2: 0, c2: 0 }
    this.renderTabs()
    this.afterChange(true)
  }

  // ================================================================ selection
  get range() {
    const { r, c, r2, c2 } = this.sel
    return { top: Math.min(r, r2), left: Math.min(c, c2), bottom: Math.max(r, r2), right: Math.max(c, c2) }
  }

  td(r, c) { return this.gridTarget.querySelector(`td[data-r="${r}"][data-c="${c}"]`) }

  paintSelection() {
    const g = this.gridTarget
    g.querySelectorAll(".sel, .cur, .hl").forEach((el) => el.classList.remove("sel", "cur", "hl"))
    const { top, left, bottom, right } = this.range
    for (let r = top; r <= bottom; r++) {
      g.querySelector(`th[data-row="${r}"]`)?.classList.add("hl")
      for (let c = left; c <= right; c++) this.td(r, c)?.classList.add("sel")
    }
    for (let c = left; c <= right; c++) g.querySelector(`th[data-col="${c}"]`)?.classList.add("hl")
    const cur = this.td(this.sel.r, this.sel.c)
    cur?.classList.add("cur")
    const multi = top !== bottom || left !== right
    if (document.activeElement !== this.nameTarget) this.nameTarget.value = multi ? `${address(top, left)}:${address(bottom, right)}` : address(this.sel.r, this.sel.c)
    if (!this.editing) this.formulaTarget.value = this.raw(this.sel.r, this.sel.c)
    this.placeFrame()
    this.updateRibbon()
    this.updateStats()
    if (!this.dragging && !this.filling && cur) this.ensureVisible(cur)
  }

  // Scrolls the grid so the cell shows (below the sticky headers); a cell wider than the view
  // shows from its left edge, like Excel.
  ensureVisible(td) {
    const wrap = this.wrapTarget
    const headW = this.gridTarget.querySelector("tbody th")?.offsetWidth || 44
    const headH = this.gridTarget.querySelector("thead th")?.offsetHeight || 20
    const left = td.offsetLeft, right = left + td.offsetWidth, top = td.offsetTop, bottom = top + td.offsetHeight
    if (left - headW < wrap.scrollLeft || td.offsetWidth > wrap.clientWidth - headW) wrap.scrollLeft = left - headW
    else if (right > wrap.scrollLeft + wrap.clientWidth) wrap.scrollLeft = right - wrap.clientWidth
    if (top - headH < wrap.scrollTop) wrap.scrollTop = top - headH
    else if (bottom > wrap.scrollTop + wrap.clientHeight) wrap.scrollTop = bottom - wrap.clientHeight
  }

  // the green selection border + the fill handle square at its bottom-right corner
  placeFrame() {
    const box0 = () => this.wrapTarget.getBoundingClientRect()
    const { top, left, bottom, right } = this.range
    const a = this.td(top, left), b = this.td(bottom, right)
    let frame = this.wrapTarget.querySelector(".sx-frame")
    if (!frame) {
      frame = document.createElement("div")
      frame.className = "sx-frame"
      frame.innerHTML = `<span class="sx-handle" title="Drag to fill"></span>`
      this.wrapTarget.appendChild(frame)
    }
    if (!a || !b || this.editing) { frame.hidden = true; return }
    if (this.catcher) {
      const cur = this.td(this.sel.r, this.sel.c)?.getBoundingClientRect()
      if (cur) Object.assign(this.catcher.style, { left: `${cur.left - box0().left + this.wrapTarget.scrollLeft}px`, top: `${cur.top - box0().top + this.wrapTarget.scrollTop}px` })
    }
    frame.hidden = false
    const box = this.wrapTarget.getBoundingClientRect()
    const ra = a.getBoundingClientRect(), rb = b.getBoundingClientRect()
    const x = ra.left - box.left + this.wrapTarget.scrollLeft, y = ra.top - box.top + this.wrapTarget.scrollTop
    Object.assign(frame.style, { left: `${x - 1}px`, top: `${y - 1}px`, width: `${rb.right - ra.left + 1}px`, height: `${rb.bottom - ra.top + 1}px` })
  }

  select(r, c, extend = false) {
    r = Math.max(0, Math.min(r, MAX_ROWS - 1))
    c = Math.max(0, Math.min(c, MAX_COLS - 1))
    if (r >= this.rows - 2 || c >= this.cols - 1) { this.minRows ||= {}; this.minRows[this.sheet] = Math.min(MAX_ROWS, r + 20); this.rows = 0; this.render() }
    this.sel = extend ? { ...this.sel, r2: r, c2: c } : { r, c, r2: r, c2: c }
    this.paintSelection()
  }

  selectAll() {
    this.sel = { r: 0, c: 0, r2: this.rows - 1, c2: this.cols - 1 }
    this.paintSelection()
  }

  goto(event) {
    if (event.key !== "Enter") return
    event.preventDefault()
    const m = this.nameTarget.value.trim().toUpperCase().match(/^([A-Z]{1,3})(\d+)(?::([A-Z]{1,3})(\d+))?$/)
    if (m) {
      this.sel = { r: +m[2] - 1, c: colIndex(m[1]), r2: m[3] ? +m[4] - 1 : +m[2] - 1, c2: m[3] ? colIndex(m[3]) : colIndex(m[1]) }
      this.paintSelection()
    }
    this.focusGrid()
  }

  // ================================================================ mouse
  mousedown(event) {
    if (event.target.closest(".sx-resize")) return this.startResize(event)
    const th = event.target.closest("th")
    if (th && event.button === 0) { // whole row / column
      this.commitEdit()
      event.preventDefault()
      if (th.dataset.col !== undefined) this.sel = { r: 0, c: +th.dataset.col, r2: this.rows - 1, c2: event.shiftKey ? this.sel.c2 : +th.dataset.col }
      if (th.dataset.row !== undefined) this.sel = { r: +th.dataset.row, c: 0, r2: event.shiftKey ? this.sel.r2 : +th.dataset.row, c2: this.cols - 1 }
      this.focusGrid()
      return this.paintSelection()
    }
    const td = event.target.closest("td")
    if (!td) return
    const r = +td.dataset.r, c = +td.dataset.c
    if (event.button === 2) { // right click inside the selection keeps it
      const { top, left, bottom, right } = this.range
      if (r < top || r > bottom || c < left || c > right) this.select(r, c)
      return
    }
    if (event.button !== 0) return
    // building a formula: clicking a cell puts its address in (like Excel)
    if (this.editing && this.editor.value.startsWith("=") && /[=(,+\-*/^&<>:]\s*$/.test(this.editor.value)) {
      event.preventDefault()
      this.editor.value += (this.sheet === this.editSheet ? "" : `'${this.current.name}'!`) + address(r, c)
      this.formulaTarget.value = this.editor.value
      this.editor.focus()
      return
    }
    this.commitEdit()
    event.preventDefault()
    this.focusGrid()
    this.select(r, c, event.shiftKey)
    this.dragging = true
  }

  handleDown(event) {
    if (!event.target.classList.contains("sx-handle")) return
    event.preventDefault()
    event.stopPropagation()
    this.commitEdit()
    this.filling = { from: { ...this.range }, to: null }
  }

  mouseover(event) {
    this.hover(event.target.closest("td"))
  }

  // the cell under the pointer while selecting / filling (also from mousemove, so fast drags work)
  hover(td) {
    if (!td || !this.gridTarget.contains(td)) return
    const r = +td.dataset.r, c = +td.dataset.c
    if (this.lastHover === td) return
    this.lastHover = td
    if (this.filling) {
      const f = this.filling.from
      const down = Math.max(0, r - f.bottom), up = Math.max(0, f.top - r), right = Math.max(0, c - f.right), left = Math.max(0, f.left - c)
      const vertical = Math.max(down, up) >= Math.max(right, left)
      this.filling.to = vertical
        ? { top: Math.min(f.top, r), bottom: Math.max(f.bottom, r), left: f.left, right: f.right }
        : { top: f.top, bottom: f.bottom, left: Math.min(f.left, c), right: Math.max(f.right, c) }
      this.sel = { r: this.filling.to.top, c: this.filling.to.left, r2: this.filling.to.bottom, c2: this.filling.to.right }
      return this.paintSelection()
    }
    if (this.dragging) this.select(r, c, true)
  }

  mouseup(event) {
    if ((this.filling || this.dragging) && event) this.hover(document.elementFromPoint(event.clientX, event.clientY)?.closest("td"))
    this.lastHover = null
    this.dragging = false
    if (this.resizing) { this.resizing = null; this.changed() }
    if (this.filling) {
      const { from, to } = this.filling
      this.filling = null
      if (to) this.fillSeries(from, to)
    }
  }

  mousemove(event) {
    if ((this.filling || this.dragging) && !this.resizing) return this.hover(document.elementFromPoint(event.clientX, event.clientY)?.closest("td"))
    if (!this.resizing) return
    const w = Math.max(24, Math.min(600, this.resizing.start + event.clientX - this.resizing.x))
    this.current.widths[this.resizing.col] = Math.round(w)
    this.gridTarget.querySelectorAll("col")[this.resizing.col + 1].style.width = `${Math.round(w)}px`
    this.placeFrame()
  }

  startResize(event) {
    event.preventDefault()
    event.stopPropagation()
    const col = +event.target.dataset.resize
    this.snapshot()
    this.resizing = { col, x: event.clientX, start: this.width(col) }
  }

  dblclick(event) {
    const handle = event.target.closest(".sx-resize")
    if (handle) { // autofit like Excel
      const c = +handle.dataset.resize
      let w = 4
      for (let r = 0; r < this.cells.length; r++) w = Math.max(w, this.display(r, c).length)
      this.snapshot()
      this.current.widths[c] = Math.min(Math.round(w * 7.4 + 14), 480)
      return this.render()
    }
    if (event.target.closest("td")) this.startEdit()
  }

  contextmenu(event) {
    if (!event.target.closest("td, th")) return
    event.preventDefault()
    event.stopPropagation() // the sheet's own menu — not a "right click" warning
    const box = this.element.getBoundingClientRect()
    const menu = this.menuTarget
    menu.hidden = false
    menu.style.left = `${Math.min(event.clientX - box.left, box.width - 220)}px`
    menu.style.top = `${Math.min(event.clientY - box.top, box.height - 330)}px`
  }

  closeMenus() {
    if (this.hasMenuTarget) this.menuTarget.hidden = true
    if (this.hasPaletteTarget) this.paletteTarget.hidden = true
  }

  menuAction(event) {
    const action = event.currentTarget.dataset.do
    this.closeMenus()
    this[action]?.()
    this.focusGrid()
  }

  // ================================================================ editing
  startEdit(initial = null) {
    if (this.editing) return
    const td = this.td(this.sel.r, this.sel.c)
    if (!td) return
    this.editing = true
    this.editSheet = this.sheet
    this.editAt = { r: this.sel.r, c: this.sel.c }
    const input = document.createElement("input")
    input.className = "sx-input"
    input.value = initial ?? this.raw(this.sel.r, this.sel.c)
    input.spellcheck = false
    input.style.cssText = td.getAttribute("style") || ""
    input.addEventListener("input", () => { this.formulaTarget.value = input.value })
    td.classList.add("editing")
    td.innerHTML = ""
    td.appendChild(input)
    this.editor = input
    this.formulaTarget.value = input.value
    this.setMode("Edit")
    this.placeFrame()
    input.focus()
    input.setSelectionRange(input.value.length, input.value.length)
  }

  commitEdit(value = null) {
    if (!this.editing) return false
    const text = value ?? this.editor.value
    const { r, c } = this.editAt
    const sheet = this.editSheet
    this.editing = false
    this.editor = null
    this.setMode("Ready")
    if (this.sheet !== sheet) { this.sheet = sheet; this.renderTabs(); this.render() }
    if (text !== this.raw(r, c, sheet)) {
      this.snapshot()
      this.put(r, c, this.autoFix(text), sheet)
      this.afterChange()
    } else {
      this.refreshValues()
    }
    return true
  }

  // "=sum(a1:a3" -> "=SUM(A1:A3)": closes brackets, upper-cases functions like Excel
  autoFix(text) {
    if (!text.startsWith("=")) return text
    let out = text.replace(/([A-Za-z_][\w.]*)\s*\(/g, (m, f) => `${f.toUpperCase()}(`)
    const open = (out.match(/\(/g) || []).length - (out.match(/\)/g) || []).length
    if (open > 0 && !/"[^"]*$/.test(out)) out += ")".repeat(open)
    return out
  }

  cancelEdit() {
    if (!this.editing) return
    this.editing = false
    this.editor = null
    this.setMode("Ready")
    this.refreshValues()
    this.focusGrid()
  }

  formulaKey(event) {
    if ((event.ctrlKey || event.metaKey) && [ "c", "x", "v" ].includes(event.key.toLowerCase())) return event.preventDefault()
    if (event.key === "Enter") {
      event.preventDefault()
      const text = this.formulaTarget.value
      if (this.editing) this.commitEdit(text)
      else if (text !== this.raw(this.sel.r, this.sel.c)) { this.snapshot(); this.put(this.sel.r, this.sel.c, this.autoFix(text)); this.afterChange() }
      this.select(this.sel.r + 1, this.sel.c)
      this.focusGrid()
    } else if (event.key === "Escape") {
      this.cancelEdit()
      this.formulaTarget.value = this.raw(this.sel.r, this.sel.c)
      this.focusGrid()
    }
  }

  formulaInput() {
    if (this.editing) this.editor.value = this.formulaTarget.value
  }

  insertFunction(event) {
    const fn = event.currentTarget.dataset.fn
    if (this.editing) {
      this.editor.value += `${this.editor.value.startsWith("=") ? "" : "="}${fn}(`
      this.editor.focus()
    } else {
      this.startEdit(`=${fn}(`)
    }
    this.formulaTarget.value = this.editor.value
  }

  // ================================================================ formatting (Home ribbon)
  eachSelected(fn) {
    const { top, left, bottom, right } = this.range
    const lastR = Math.min(bottom, Math.max(top, this.rows - 1)), lastC = Math.min(right, Math.max(left, this.cols - 1))
    for (let r = top; r <= lastR; r++) for (let c = left; c <= lastC; c++) fn(r, c)
  }

  setStyle(patch) {
    this.commitEdit()
    this.snapshot()
    const touchedCols = new Set()
    this.eachSelected((r, c) => {
      touchedCols.add(c)
      const key = `${r}:${c}`
      const st = { ...(this.current.styles[key] || {}), ...patch }
      Object.keys(st).forEach((k) => { if (st[k] === null || st[k] === false || st[k] === "") delete st[k] })
      if (Object.keys(st).length) this.current.styles[key] = st
      else delete this.current.styles[key]
    })
    // a number format or bigger font can make values wider: widen the column like Excel does
    if ("fmt" in patch || "d" in patch || "fs" in patch || "b" in patch) {
      this.book.invalidate()
      touchedCols.forEach((c) => {
        let w = 0
        for (let r = 0; r < Math.min(this.cells.length, 400); r++) {
          if (typeof this.value(r, c) !== "number") continue
          const st = this.styleOf(r, c)
          w = Math.max(w, this.display(r, c).length * (st.fs ? st.fs / 11 : 1) * (st.b ? 1.08 : 1))
        }
        const need = Math.round(w * 7.6 + 16)
        if (need > this.width(c)) this.current.widths[c] = Math.min(need, 360)
      })
    }
    this.afterChange(true)
  }

  toggle(event) {
    const key = event.currentTarget?.dataset?.style || event
    const on = !this.styleOf(this.sel.r, this.sel.c)[key]
    this.setStyle({ [key]: on })
  }

  bold() { this.toggle("b") }
  italic() { this.toggle("i") }
  underline() { this.toggle("u") }
  wrapText() { this.toggle("w") }
  align(event) { const al = event.currentTarget.dataset.align; this.setStyle({ al: this.styleOf(this.sel.r, this.sel.c).al === al ? null : al }) }
  fontSize() { this.setStyle({ fs: Number(this.fontSizeTarget.value) === 11 ? null : Number(this.fontSizeTarget.value) }) }
  numberFormat() { this.setStyle({ fmt: this.numberFormatTarget.value === "general" ? null : this.numberFormatTarget.value, d: null }) }
  currency() { this.setStyle({ fmt: "currency", d: null }) }
  percent() { this.setStyle({ fmt: "percent", d: null }) }
  comma() { this.setStyle({ fmt: "comma", d: null }) }

  decimals(event) {
    const step = Number(event.currentTarget.dataset.step)
    const st = this.styleOf(this.sel.r, this.sel.c)
    const fmt = st.fmt || "number"
    const base = Number.isInteger(st.d) ? st.d : (st.fmt ? { number: 2, currency: 2, percent: 0, comma: 0 }[fmt] : this.currentDecimals())
    this.setStyle({ fmt, d: Math.max(0, Math.min(6, base + step)) })
  }

  currentDecimals() {
    const v = this.value(this.sel.r, this.sel.c)
    if (typeof v !== "number") return 0
    const s = formatNumber(v)
    return s.includes(".") ? s.split(".")[1].length : 0
  }

  openPalette(event) {
    event.preventDefault()
    const kind = event.currentTarget.dataset.palette
    const box = this.element.getBoundingClientRect(), btn = event.currentTarget.getBoundingClientRect()
    const p = this.paletteTarget
    p.innerHTML = `<button type="button" class="sx-nocolor" data-color="" data-kind="${kind}" data-action="sheet-editor#pickColor">${kind === "bg" ? "No fill" : "Automatic"}</button>` +
      `<div class="sx-swatches">${PALETTE.map((col) => `<button type="button" style="background:${col}" title="${col}" data-color="${col}" data-kind="${kind}" data-action="sheet-editor#pickColor"></button>`).join("")}</div>`
    p.style.left = `${btn.left - box.left}px`
    p.style.top = `${btn.bottom - box.top + 4}px`
    p.hidden = false
  }

  pickColor(event) {
    const { color, kind } = event.currentTarget.dataset
    this.closeMenus()
    this.lastColor ||= {}
    this.lastColor[kind] = color
    this.setStyle({ [kind]: color || null })
    this.focusGrid()
  }

  applyLastColor(event) {
    const kind = event.currentTarget.dataset.kind
    const color = this.lastColor?.[kind] ?? (kind === "bg" ? "#ffff00" : "#c00000")
    this.setStyle({ [kind]: color || null })
  }

  updateRibbon() {
    if (!this.hasRibbonTarget) return
    const st = this.styleOf(this.sel.r, this.sel.c)
    this.ribbonTarget.querySelectorAll("[data-state]").forEach((b) => {
      const k = b.dataset.state
      b.classList.toggle("on", k.startsWith("al:") ? st.al === k.slice(3) : !!st[k])
    })
    if (this.hasFontSizeTarget) this.fontSizeTarget.value = String(st.fs || 11)
    if (this.hasNumberFormatTarget) this.numberFormatTarget.value = st.fmt || "general"
  }

  // ================================================================ cells (insert / delete / clear)
  clearSelection() {
    this.snapshot()
    this.eachSelected((r, c) => { if (this.raw(r, c) !== "") this.put(r, c, "") })
    this.afterChange()
  }

  clearAll() {
    this.snapshot()
    this.eachSelected((r, c) => { if (this.raw(r, c) !== "") this.put(r, c, ""); delete this.current.styles[`${r}:${c}`] })
    this.afterChange(true)
  }

  insertRows() { const { top, bottom } = this.range; this.shiftCells("row", top, bottom - top + 1) }
  deleteRows() { const { top, bottom } = this.range; this.shiftCells("row", top, -(bottom - top + 1)) }
  insertCols() { const { left, right } = this.range; this.shiftCells("col", left, right - left + 1) }
  deleteCols() { const { left, right } = this.range; this.shiftCells("col", left, -(right - left + 1)) }

  // Inserts (count > 0) or deletes (count < 0) rows / columns; every formula in the workbook follows.
  shiftCells(axis, at, count) {
    this.commitEdit()
    this.snapshot()
    const target = this.current.name
    const s = this.current
    const del = count < 0 ? -count : 0
    if (axis === "row") {
      if (count > 0) s.cells.splice(at, 0, ...Array.from({ length: count }, () => []))
      else s.cells.splice(at, del)
    } else {
      s.cells.forEach((row) => {
        if (count > 0) { if (row.length > at) row.splice(at, 0, ...Array(count).fill("")) } else row.splice(at, del)
      })
    }
    const styles = {}
    Object.entries(s.styles).forEach(([ key, st ]) => {
      let [ r, c ] = key.split(":").map(Number)
      let i = axis === "row" ? r : c
      if (count > 0 && i >= at) i += count
      else if (count < 0) { if (i >= at && i < at + del) return; if (i >= at + del) i -= del }
      if (axis === "row") r = i; else c = i
      styles[`${r}:${c}`] = st
    })
    s.styles = styles
    if (axis === "col") {
      const widths = {}
      Object.entries(s.widths).forEach(([ k, w ]) => {
        let c = Number(k)
        if (count > 0 && c >= at) c += count
        else if (count < 0) { if (c >= at && c < at + del) return; if (c >= at + del) c -= del }
        widths[c] = w
      })
      s.widths = widths
    }
    this.book.sheets.forEach((sheet) => sheet.cells.forEach((row) => row.forEach((v, c) => {
      if (typeof v === "string" && v.startsWith("=")) row[c] = adjustReferences(v, { axis, at, count, target, home: sheet.name })
    })))
    this.afterChange(true)
  }

  // ================================================================ copy / paste / fill
  copy(cut = false) {
    const { top, left, bottom, right } = this.range
    const grid = [], styles = []
    for (let r = top; r <= bottom; r++) {
      const row = [], srow = []
      for (let c = left; c <= right; c++) { row.push(this.raw(r, c)); srow.push(this.styleOf(r, c)) }
      grid.push(row); styles.push(srow)
    }
    this.clip = { grid, styles, top, left, sheet: this.sheet, cut }
    this.gridTarget.querySelectorAll(".clip").forEach((el) => el.classList.remove("clip"))
    this.eachSelected((r, c) => this.td(r, c)?.classList.add("clip"))
    this.setMode(cut ? "Select destination and press Enter or Ctrl+V" : "Select destination and press Ctrl+V")
  }

  paste() {
    if (!this.clip) return
    this.snapshot()
    const { grid, styles, top, left, cut, sheet } = this.clip
    const { top: dt, left: dl, bottom: db, right: dr } = this.range
    const rows = db > dt && (db - dt + 1) % grid.length === 0 ? db - dt + 1 : grid.length
    const cols = dr > dl && (dr - dl + 1) % grid[0].length === 0 ? dr - dl + 1 : grid[0].length
    if (cut) grid.forEach((row, i) => row.forEach((_, j) => { this.put(top + i, left + j, "", sheet); delete this.book.sheets[sheet].styles[`${top + i}:${left + j}`] }))
    for (let i = 0; i < rows; i++) {
      for (let j = 0; j < cols; j++) {
        const gi = i % grid.length, gj = j % grid[0].length
        const v = cut ? grid[gi][gj] : shiftFormula(grid[gi][gj], dt + i - (top + gi), dl + j - (left + gj))
        this.put(dt + i, dl + j, v)
        const st = styles[gi][gj]
        if (Object.keys(st).length) this.current.styles[`${dt + i}:${dl + j}`] = { ...st }
        else delete this.current.styles[`${dt + i}:${dl + j}`]
      }
    }
    if (cut) this.clip = null
    this.sel = { r: dt, c: dl, r2: dt + rows - 1, c2: dl + cols - 1 }
    this.setMode("Ready")
    this.afterChange(true)
  }

  copyCells() { this.copy() }
  cutCells() { this.copy(true) }

  // Ctrl+D / Ctrl+R: the first row / column of the selection copied across (formulas adjust)
  fillDown() {
    let { top, left, bottom, right } = this.range
    if (top === bottom) { if (top === 0) return; top -= 1 }
    this.fillSeries({ top, left, bottom: top, right }, { top, left, bottom, right }, false)
  }

  fillRight() {
    let { top, left, bottom, right } = this.range
    if (left === right) { if (left === 0) return; left -= 1 }
    this.fillSeries({ top, left, bottom, right: left }, { top, left, bottom, right }, false)
  }

  // Fill handle: copies the source block over the target; 2+ numbers in a line make a series (1, 2, 3…)
  fillSeries(from, to, series = true) {
    this.snapshot()
    const vertical = to.left === from.left && to.right === from.right
    const lines = vertical ? [ from.left, from.right ] : [ from.top, from.bottom ]
    for (let line = lines[0]; line <= lines[1]; line++) {
      const src = []
      const a = vertical ? from.top : from.left, b = vertical ? from.bottom : from.right
      for (let i = a; i <= b; i++) src.push(vertical ? [ i, line ] : [ line, i ])
      const nums = src.map(([ r, c ]) => literal(this.raw(r, c)))
      const isSeries = series && src.length >= 2 && nums.every((n) => typeof n === "number")
      const step = isSeries ? (nums[nums.length - 1] - nums[0]) / (nums.length - 1) : 0
      const start = vertical ? to.top : to.left, end = vertical ? to.bottom : to.right
      for (let i = start; i <= end; i++) {
        if (i >= a && i <= b) continue
        const k = ((i - a) % src.length + src.length) % src.length
        const [ sr, sc ] = src[k]
        const [ r, c ] = vertical ? [ i, line ] : [ line, i ]
        const v = isSeries ? formatNumber(nums[0] + step * (i - a)) : shiftFormula(this.raw(sr, sc), r - sr, c - sc)
        this.put(r, c, v)
        const st = this.styleOf(sr, sc)
        if (Object.keys(st).length) this.current.styles[`${r}:${c}`] = { ...st }
      }
    }
    this.sel = { r: to.top, c: to.left, r2: to.bottom, c2: to.right }
    this.afterChange(true)
  }

  // ================================================================ AutoSum, sort
  autoSum() {
    this.commitEdit()
    const { top, left, bottom, right } = this.range
    const isNum = (r, c) => typeof this.value(r, c) === "number"
    if (bottom > top || right > left) { // a block: totals under each column
      this.snapshot()
      for (let c = left; c <= right; c++) this.put(bottom + 1, c, `=SUM(${address(top, c)}:${address(bottom, c)})`)
      this.sel = { r: bottom + 1, c: left, r2: bottom + 1, c2: right }
      return this.afterChange(true)
    }
    const r = top, c = left
    let a = r - 1
    while (a >= 0 && !isNum(a, c)) a--
    let first = a
    while (first - 1 >= 0 && isNum(first - 1, c)) first--
    if (a >= 0) return this.startEdit(`=SUM(${address(first, c)}:${address(a, c)})`)
    let b = c - 1
    while (b >= 0 && !isNum(r, b)) b--
    let firstC = b
    while (firstC - 1 >= 0 && isNum(r, firstC - 1)) firstC--
    this.startEdit(b >= 0 ? `=SUM(${address(r, firstC)}:${address(r, b)})` : "=SUM(")
  }

  sortAsc() { this.sort(1) }
  sortDesc() { this.sort(-1) }

  // Sorts the selected rows (or the data block around the cell, keeping its header row) by the active column.
  sort(dir) {
    this.commitEdit()
    let { top, bottom, left, right } = this.range
    if (top === bottom) {
      // the data block under the header: rows down from row 2 while its first column has a value
      // (a "Total" row with an empty first cell stays where it is)
      top = 1
      bottom = top
      while (bottom + 1 < this.cells.length && this.raw(bottom + 1, 0) !== "") bottom++
      left = 0
      right = this.cells.slice(0, bottom + 1).reduce((m, row) => Math.max(m, row.length), 1) - 1
      if (bottom <= top || this.raw(top, 0) === "") return
    }
    const key = this.sel.c
    this.snapshot()
    const rows = []
    for (let r = top; r <= bottom; r++) rows.push({ r, v: this.value(r, key) })
    rows.sort((x, y) => {
      const a = x.v, b = y.v
      const ea = a === null || a === "", eb = b === null || b === ""
      if (ea || eb) return ea === eb ? 0 : ea ? 1 : -1 // blanks last
      if (typeof a === "number" && typeof b === "number") return (a - b) * dir
      if (typeof a === "number") return -dir
      if (typeof b === "number") return dir
      return String(a).localeCompare(String(b), undefined, { sensitivity: "base" }) * dir
    })
    const old = rows.map(({ r }) => ({ r, cells: Array.from({ length: right - left + 1 }, (_, j) => this.raw(r, left + j)),
                                       styles: Array.from({ length: right - left + 1 }, (_, j) => this.styleOf(r, left + j)) }))
    old.forEach((src, i) => {
      const r = top + i
      src.cells.forEach((v, j) => {
        this.put(r, left + j, shiftFormula(v, r - src.r, 0))
        const st = src.styles[j]
        if (Object.keys(st).length) this.current.styles[`${r}:${left + j}`] = { ...st }
        else delete this.current.styles[`${r}:${left + j}`]
      })
    })
    this.afterChange(true)
  }

  // ================================================================ view
  zoomIn() { this.setZoom(this.zoom + 0.1) }
  zoomOut() { this.setZoom(this.zoom - 0.1) }
  setZoom(z) {
    this.zoom = Math.round(Math.max(0.6, Math.min(1.6, z)) * 10) / 10
    this.gridTarget.style.setProperty("--sx-zoom", this.zoom)
    if (this.hasZoomLabelTarget) this.zoomLabelTarget.textContent = `${Math.round(this.zoom * 100)}%`
    this.placeFrame()
  }

  ribbonTab(event) {
    const tab = event.currentTarget.dataset.tab
    this.element.querySelectorAll("[data-ribbon-tab]").forEach((b) => b.classList.toggle("active", b.dataset.ribbonTab === tab))
    this.element.querySelectorAll("[data-ribbon-panel]").forEach((p) => { p.hidden = p.dataset.ribbonPanel !== tab })
  }

  toggleHelp() {
    if (!this.helpTarget.innerHTML) {
      this.helpTarget.innerHTML = `<b>Formulas start with =</b> — e.g. <code>=E2*F2</code>, <code>=SUM(G2:G13)</code>, <code>=VLOOKUP(C2,'Price List'!A:B,2,FALSE)</code>
        <ul>${COMMON_FUNCTIONS.map(([ f, d ]) => `<li><code>${esc(f)}</code> ${esc(d)}</li>`).join("")}</ul>
        <p><b>Keys:</b> Enter / Tab move · F2 or double-click edits · Delete clears · Ctrl+C / X / V copy inside the sheet (formulas adjust) · drag the small square at the corner of the selection to fill · Ctrl+D fill down · Ctrl+R fill right · Ctrl+B / I / U · Ctrl+Z / Ctrl+Y undo / redo · Alt+= AutoSum · Shift+arrows select · right-click for Insert / Delete. While typing a formula, click a cell to insert its address.</p>`
    }
    this.helpTarget.hidden = !this.helpTarget.hidden
  }

  // Full view: the sheet takes the page, but the header (timer, warnings, Submit) and the
  // camera stay on screen — proctoring, recording and screen share carry on as before.
  expand() {
    this.element.classList.toggle("sx-expanded")
    const open = this.element.classList.contains("sx-expanded")
    document.body.classList.toggle("sx-open", open)
    document.querySelector(".sx-backdrop")?.remove()
    if (open) document.body.insertAdjacentHTML("beforeend", `<div class="sx-backdrop"></div>`)
    const header = document.querySelector(".exam-top")
    document.body.style.setProperty("--sx-top", `${header ? header.offsetHeight : 0}px`)
    const cam = document.querySelector(".exam-side .cam-wrap")
    document.body.style.setProperty("--sx-cam", `${cam && window.innerWidth <= 760 ? cam.offsetHeight + 12 : 0}px`)
    requestAnimationFrame(() => this.placeFrame())
    this.focusGrid()
  }

  updateStats() {
    if (!this.hasStatsTarget) return
    const { top, left, bottom, right } = this.range
    if (top === bottom && left === right) { this.statsTarget.textContent = ""; return }
    let sum = 0, nums = 0, count = 0
    const lastR = Math.min(bottom, this.cells.length - 1)
    for (let r = top; r <= lastR; r++) for (let c = left; c <= right; c++) {
      const v = this.value(r, c)
      if (v === null || v === "" || v === undefined) continue
      count++
      if (typeof v === "number") { sum += v; nums++ }
    }
    const f = (n) => new Intl.NumberFormat("en-IN", { maximumFractionDigits: 2 }).format(n)
    this.statsTarget.textContent = nums ? `Average: ${f(sum / nums)}    Count: ${count}    Sum: ${f(sum)}` : count ? `Count: ${count}` : ""
  }

  setMode(text) {
    if (this.hasModeTarget) this.modeTarget.textContent = text
  }

  focusGrid() {
    if (this.catcher) this.catcher.focus({ preventScroll: true })
    else this.gridTarget.focus({ preventScroll: true })
  }

  // ================================================================ keyboard
  keydown(e) {
    const mod = e.ctrlKey || e.metaKey
    const k = e.key
    if (this.editing) {
      if (k === "Enter" || k === "Tab") {
        e.preventDefault()
        this.commitEdit()
        if (k === "Tab") this.select(this.sel.r, this.sel.c + (e.shiftKey ? -1 : 1))
        else this.select(this.sel.r + (e.shiftKey ? -1 : 1), this.sel.c)
        this.focusGrid()
      } else if (k === "Escape") {
        e.preventDefault()
        this.cancelEdit()
      } else if (mod && [ "c", "x", "v" ].includes(k.toLowerCase())) {
        e.preventDefault() // no system clipboard while typing in a cell
      }
      return
    }
    if (e.altKey && (k === "=" || k === "+")) { e.preventDefault(); return this.autoSum() }
    if (mod) {
      const key = k.toLowerCase()
      const actions = { c: () => this.copy(), x: () => this.copy(true), v: () => this.paste(), d: () => this.fillDown(), r: () => this.fillRight(),
                        z: () => this.undo(), y: () => this.redo(), s: () => this.save(), a: () => this.selectAll(),
                        b: () => this.bold(), i: () => this.italic(), u: () => this.underline(),
                        home: () => this.select(0, 0) }
      if (actions[key]) { e.preventDefault(); actions[key]() }
      if (k.startsWith("Arrow")) { e.preventDefault(); this.jump(k, e.shiftKey) }
      return
    }
    if (k === "Escape" && this.clip) { this.clip = null; this.gridTarget.querySelectorAll(".clip").forEach((el) => el.classList.remove("clip")); return this.setMode("Ready") }
    const moves = { ArrowUp: [ -1, 0 ], ArrowDown: [ 1, 0 ], ArrowLeft: [ 0, -1 ], ArrowRight: [ 0, 1 ], Enter: [ 1, 0 ], Tab: [ 0, 1 ] }
    if (k === "Enter" && this.clip) { e.preventDefault(); return this.paste() }
    if (moves[k]) {
      e.preventDefault()
      let [ dr, dc ] = moves[k]
      if ((k === "Enter" || k === "Tab") && e.shiftKey) { dr = -dr; dc = -dc }
      const extend = e.shiftKey && k.startsWith("Arrow")
      const from = extend ? { r: this.sel.r2, c: this.sel.c2 } : this.sel
      return this.select(from.r + dr, from.c + dc, extend)
    }
    if (k === "Home") { e.preventDefault(); return this.select(this.sel.r, 0) }
    if (k === "PageDown" || k === "PageUp") { e.preventDefault(); return this.select(this.sel.r + (k === "PageDown" ? 20 : -20), this.sel.c) }
    if (k === "F2") { e.preventDefault(); return this.startEdit() }
    if (k === "Delete" || k === "Backspace") { e.preventDefault(); return this.clearSelection() }
    // a typed character arrives as "input" on the catcher (works for every keyboard)
  }

  // Ctrl+arrow: to the edge of the data, like Excel
  jump(k, extend) {
    const [ dr, dc ] = { ArrowUp: [ -1, 0 ], ArrowDown: [ 1, 0 ], ArrowLeft: [ 0, -1 ], ArrowRight: [ 0, 1 ] }[k]
    let r = extend ? this.sel.r2 : this.sel.r, c = extend ? this.sel.c2 : this.sel.c
    const filled = (rr, cc) => this.raw(rr, cc) !== ""
    const inside = (rr, cc) => rr >= 0 && cc >= 0 && rr < this.rows && cc < this.cols
    if (inside(r + dr, c + dc) && filled(r, c) && filled(r + dr, c + dc)) {
      while (inside(r + dr, c + dc) && filled(r + dr, c + dc)) { r += dr; c += dc }
    } else {
      r += dr; c += dc
      while (inside(r + dr, c + dc) && !filled(r, c)) { r += dr; c += dc }
    }
    this.select(r, c, extend)
  }

  // ================================================================ saving
  changed() {
    this.dirty = true
    this.setStatus("Saving…")
    clearTimeout(this.debounce)
    this.debounce = setTimeout(() => this.save(), 1500)
  }

  async save() {
    if (this.editing) this.commitEdit()
    clearTimeout(this.debounce)
    if (!this.book || !this.dirty) return
    this.dirty = false
    const sheets = this.book.sheets.map((s, si) => ({
      name: s.name,
      cells: s.cells,
      values: s.cells.map((row, r) => row.map((raw, c) => (String(raw).startsWith("=") ? this.plain(si, r, c) : ""))),
      styles: s.styles,
      widths: s.widths
    }))
    try {
      const res = await fetch(this.saveUrlValue, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
        body: JSON.stringify({ sheets })
      })
      if (!res.ok) throw new Error(res.status)
      this.setStatus(`Saved · ${new Date().toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}`)
    } catch {
      this.dirty = true
      this.setStatus("Not saved — retrying…", true)
      this.debounce = setTimeout(() => this.save(), 5000)
    }
  }

  plain(si, r, c) {
    const v = this.book.value(si, r, c)
    if (v === null || v === undefined) return ""
    if (isError(v)) return v.code || v.message
    return typeof v === "number" ? formatNumber(v) : typeof v === "boolean" ? (v ? "TRUE" : "FALSE") : String(v)
  }

  setStatus(text, bad = false) {
    this.statusTargets.forEach((el) => {
      el.textContent = text
      el.classList.toggle("bad", bad)
    })
  }
}
