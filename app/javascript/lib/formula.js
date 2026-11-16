// A small Excel-style formula engine for the built-in spreadsheet of practical assessments.
// Parses "=SUM(A1:A5)*2", "='Price List'!B2", "=VLOOKUP(C2,'Price List'!A:B,2,FALSE)" … and
// evaluates them against the workbook. The Excel functions themselves come from formula.js (MIT).

const FORMULAJS = "https://cdn.jsdelivr.net/npm/@formulajs/formulajs@4.6.1/+esm"
let fnLoader
export function loadFunctions() {
  fnLoader ||= import(FORMULAJS).then((m) => m.default && Object.keys(m).length <= 2 ? m.default : m).catch((e) => {
    console.warn("formula.js unavailable — basic functions only", e)
    return {}
  })
  return fnLoader
}

// ---- addresses -------------------------------------------------------------
export function colName(index) {
  let s = ""
  for (let n = index + 1; n > 0; n = Math.floor((n - 1) / 26)) s = String.fromCharCode(65 + ((n - 1) % 26)) + s
  return s
}
export function colIndex(name) {
  let n = 0
  for (const ch of name.toUpperCase()) n = n * 26 + (ch.charCodeAt(0) - 64)
  return n - 1
}
export const address = (r, c) => `${colName(c)}${r + 1}`

// ---- errors ----------------------------------------------------------------
export class CellError {
  constructor(code) { this.code = code }
  toString() { return this.code }
}
const err = (code) => new CellError(code)
export const isError = (v) => v instanceof CellError || v instanceof Error
const errorCode = (v) => (v instanceof CellError ? v.code : (v?.message?.startsWith("#") ? v.message : "#VALUE!"))

// ---- tokenizer (keeps every character, so formulas can be rebuilt after shifting refs) ----
const REF = /^(\$?)([A-Za-z]{1,3})(\$?)(\d+)/
const COLREF = /^(\$?)([A-Za-z]{1,3}):(\$?)([A-Za-z]{1,3})(?![\w(])/

export function tokenize(src) {
  const tokens = []
  let i = 0
  while (i < src.length) {
    const rest = src.slice(i)
    const ch = src[i]
    let m
    if (/\s/.test(ch)) { m = rest.match(/^\s+/); tokens.push({ t: "ws", v: m[0] }); i += m[0].length; continue }
    if (ch === '"') {
      let j = i + 1, s = ""
      while (j < src.length) {
        if (src[j] === '"' && src[j + 1] === '"') { s += '"'; j += 2; continue }
        if (src[j] === '"') break
        s += src[j++]
      }
      tokens.push({ t: "str", v: s, raw: src.slice(i, j + 1) }); i = j + 1; continue
    }
    // sheet prefix: 'Price List'!  or  Sheet2!
    let sheet = null, sheetRaw = ""
    if ((m = rest.match(/^'((?:[^']|'')+)'!/)) || (m = rest.match(/^([A-Za-z_][\w.]*)!/))) {
      sheet = m[1].replace(/''/g, "'"); sheetRaw = m[0]
    }
    const after = rest.slice(sheetRaw.length)
    if ((m = after.match(COLREF))) {
      tokens.push({ t: "colrange", sheet, sheetRaw, a: { abs: !!m[1], col: colIndex(m[2]) }, b: { abs: !!m[3], col: colIndex(m[4]) } })
      i += sheetRaw.length + m[0].length; continue
    }
    if ((m = after.match(REF)) && !/^[\w(]/.test(after.slice(m[0].length))) {
      tokens.push({ t: "ref", sheet, sheetRaw, absC: !!m[1], col: colIndex(m[2]), absR: !!m[3], row: Number(m[4]) - 1 })
      i += sheetRaw.length + m[0].length; continue
    }
    if (sheetRaw) { tokens.push({ t: "bad", v: sheetRaw }); i += sheetRaw.length; continue }
    if ((m = rest.match(/^\d+(\.\d+)?([eE][+-]?\d+)?|^\.\d+/))) { tokens.push({ t: "num", v: Number(m[0]), raw: m[0] }); i += m[0].length; continue }
    if ((m = rest.match(/^[A-Za-z_][\w.]*(?=\s*\()/))) { tokens.push({ t: "fn", v: m[0].toUpperCase(), raw: m[0] }); i += m[0].length; continue }
    if ((m = rest.match(/^(TRUE|FALSE)(?![\w(])/i))) { tokens.push({ t: "bool", v: m[1].toUpperCase() === "TRUE", raw: m[0] }); i += m[0].length; continue }
    if ((m = rest.match(/^(<>|<=|>=|[-+*/^&=<>%(),:;])/))) { tokens.push({ t: "op", v: m[1] === ";" ? "," : m[1], raw: m[1] }); i += m[1].length; continue }
    if ((m = rest.match(/^[A-Za-z_][\w.]*/))) { tokens.push({ t: "name", v: m[0], raw: m[0] }); i += m[0].length; continue }
    tokens.push({ t: "bad", v: ch }); i += 1
  }
  return tokens
}

// ---- parser ----------------------------------------------------------------
export function parse(formula) {
  const tokens = tokenize(formula).filter((t) => t.t !== "ws")
  let p = 0
  const peek = () => tokens[p]
  const isOp = (v) => peek()?.t === "op" && peek().v === v
  const take = () => tokens[p++]
  const expect = (v) => { if (!isOp(v)) throw err("#ERROR!"); p++ }

  function comparison() {
    let left = concat()
    while (peek()?.t === "op" && [ "=", "<>", "<", ">", "<=", ">=" ].includes(peek().v)) left = { k: "bin", op: take().v, left, right: concat() }
    return left
  }
  function concat() {
    let left = additive()
    while (isOp("&")) { take(); left = { k: "bin", op: "&", left, right: additive() } }
    return left
  }
  function additive() {
    let left = multiplicative()
    while (isOp("+") || isOp("-")) left = { k: "bin", op: take().v, left, right: multiplicative() }
    return left
  }
  function multiplicative() {
    let left = power()
    while (isOp("*") || isOp("/")) left = { k: "bin", op: take().v, left, right: power() }
    return left
  }
  function power() {
    let left = unary()
    while (isOp("^")) { take(); left = { k: "bin", op: "^", left, right: unary() } }
    return left
  }
  function unary() {
    if (isOp("-")) { take(); return { k: "neg", e: unary() } }
    if (isOp("+")) { take(); return unary() }
    let e = primary()
    while (isOp("%")) { take(); e = { k: "pct", e } }
    return e
  }
  function primary() {
    const tk = take()
    if (!tk) throw err("#ERROR!")
    switch (tk.t) {
      case "num": return { k: "lit", v: tk.v }
      case "str": return { k: "lit", v: tk.v }
      case "bool": return { k: "lit", v: tk.v }
      case "colrange": return { k: "range", sheet: tk.sheet, r1: 0, c1: Math.min(tk.a.col, tk.b.col), r2: Infinity, c2: Math.max(tk.a.col, tk.b.col) }
      case "ref": {
        if (isOp(":") && tokens[p + 1]?.t === "ref") {
          take(); const b = take()
          return { k: "range", sheet: tk.sheet, r1: Math.min(tk.row, b.row), c1: Math.min(tk.col, b.col), r2: Math.max(tk.row, b.row), c2: Math.max(tk.col, b.col) }
        }
        return { k: "ref", sheet: tk.sheet, r: tk.row, c: tk.col }
      }
      case "fn": {
        expect("(")
        const args = []
        if (!isOp(")")) {
          do { args.push(isOp(",") || isOp(")") ? { k: "lit", v: null } : comparison()) } while (isOp(",") && take())
        }
        expect(")")
        return { k: "fn", name: tk.v, args }
      }
      case "op":
        if (tk.v === "(") { const e = comparison(); expect(")"); return e }
        break
      case "name": return { k: "lit", v: err("#NAME?") }
    }
    throw err("#ERROR!")
  }

  const ast = comparison()
  if (p < tokens.length) throw err("#ERROR!")
  return ast
}

// ---- moving formulas (copy / paste, fill down) -------------------------------
// Shifts relative references by (dr, dc) like Excel; $-anchored parts stay. Off-sheet -> #REF!
export function shiftFormula(text, dr, dc) {
  if (typeof text !== "string" || !text.startsWith("=")) return text
  return "=" + tokenize(text.slice(1)).map((tk) => {
    if (tk.t === "ref") {
      const r = tk.absR ? tk.row : tk.row + dr
      const c = tk.absC ? tk.col : tk.col + dc
      if (r < 0 || c < 0) return "#REF!"
      return `${tk.sheetRaw}${tk.absC ? "$" : ""}${colName(c)}${tk.absR ? "$" : ""}${r + 1}`
    }
    if (tk.t === "colrange") {
      const a = tk.a.abs ? tk.a.col : tk.a.col + dc
      const b = tk.b.abs ? tk.b.col : tk.b.col + dc
      if (a < 0 || b < 0) return "#REF!"
      return `${tk.sheetRaw}${tk.a.abs ? "$" : ""}${colName(a)}:${tk.b.abs ? "$" : ""}${colName(b)}`
    }
    return tk.raw ?? tk.v
  }).join("")
}

// ---- evaluation --------------------------------------------------------------
// Turns what is typed in a cell into a value: "12" -> 12, "TRUE" -> true, "" -> null.
export function literal(raw) {
  if (raw === null || raw === undefined || raw === "") return null
  const s = String(raw)
  if (/^[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?$/.test(s.trim())) return Number(s)
  if (/^[-+]?\d+(\.\d+)?%$/.test(s.trim())) return Number(s.trim().slice(0, -1)) / 100
  if (/^(true|false)$/i.test(s.trim())) return s.trim().toUpperCase() === "TRUE"
  return s
}

// Dates are typed / shown as yyyy-mm-dd; in sums they count as Excel day numbers (1 = 1900-01-01).
const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})$/
const isDate = (v) => typeof v === "string" && ISO_DATE.test(v)
const EPOCH = Date.UTC(1899, 11, 30)
export const dateSerial = (s) => { const [ , y, m, d ] = s.match(ISO_DATE); return Math.round((Date.UTC(+y, +m - 1, +d) - EPOCH) / 86400000) }
export const serialDate = (n) => new Date(EPOCH + Math.round(n) * 86400000).toISOString().slice(0, 10)

const toNumber = (v) => {
  if (isError(v)) return v
  if (v === null || v === undefined || v === "") return 0
  if (typeof v === "number") return v
  if (typeof v === "boolean") return v ? 1 : 0
  if (isDate(v)) return dateSerial(v)
  const n = literal(v)
  return typeof n === "number" ? n : err("#VALUE!")
}
const toText = (v) => (v === null || v === undefined ? "" : typeof v === "boolean" ? (v ? "TRUE" : "FALSE") : typeof v === "number" ? formatNumber(v) : String(v))

export function formatNumber(n) {
  if (!Number.isFinite(n)) return "#NUM!"
  return Number.isInteger(n) ? String(n) : String(Number(n.toPrecision(12)))
}

const LAZY = new Set([ "IF", "IFERROR", "IFNA", "IFS", "AND", "OR" ])

// A workbook: [{ name, cells: [[raw]] }]. Values are computed on demand and cached until the next edit.
export class Workbook {
  constructor(sheets, fns = {}) {
    this.sheets = sheets
    this.fns = fns
    this.invalidate()
  }

  invalidate() {
    this.cache = new Map()
    this.parsed ||= new Map()
  }

  sheetIndex(name, current) {
    if (name === null || name === undefined) return current
    const i = this.sheets.findIndex((s) => s.name.toLowerCase() === String(name).toLowerCase())
    return i
  }

  raw(si, r, c) {
    return this.sheets[si]?.cells?.[r]?.[c] ?? ""
  }

  // The computed value of a cell (number / string / boolean / null / CellError).
  value(si, r, c, stack = new Set()) {
    const key = `${si}:${r}:${c}`
    if (this.cache.has(key)) return this.cache.get(key)
    const raw = this.raw(si, r, c)
    let v
    if (typeof raw === "string" && raw.startsWith("=") && raw.length > 1) {
      if (stack.has(key)) return err("#CIRCULAR!")
      stack.add(key)
      try {
        let ast = this.parsed.get(raw)
        if (!ast) { ast = parse(raw.slice(1)); this.parsed.set(raw, ast) }
        v = this.evaluate(ast, si, stack)
        if (Array.isArray(v)) v = v[0]?.[0] ?? null // a range typed alone: its first cell
        if (v === null || v === undefined) v = 0
      } catch (e) {
        v = isError(e) ? (e instanceof CellError ? e : err("#ERROR!")) : err("#ERROR!")
      }
      stack.delete(key)
    } else {
      v = literal(raw)
    }
    this.cache.set(key, v)
    return v
  }

  usedRows(si) {
    return this.sheets[si]?.cells?.length || 0
  }

  rangeValues(node, si, stack) {
    const s = this.sheetIndex(node.sheet, si)
    if (s < 0) return err("#REF!")
    const r2 = node.r2 === Infinity ? this.usedRows(s) - 1 : node.r2
    const out = []
    for (let r = node.r1; r <= r2; r++) {
      const row = []
      for (let c = node.c1; c <= node.c2; c++) row.push(this.value(s, r, c, stack))
      out.push(row)
    }
    return out
  }

  evaluate(node, si, stack) {
    switch (node.k) {
      case "lit": return node.v
      case "ref": {
        const s = this.sheetIndex(node.sheet, si)
        return s < 0 ? err("#REF!") : this.value(s, node.r, node.c, stack)
      }
      case "range": return this.rangeValues(node, si, stack)
      case "neg": { const v = toNumber(this.scalar(node.e, si, stack)); return isError(v) ? v : -v }
      case "pct": { const v = toNumber(this.scalar(node.e, si, stack)); return isError(v) ? v : v / 100 }
      case "bin": return this.binary(node, si, stack)
      case "fn": return this.call(node, si, stack)
    }
    return err("#ERROR!")
  }

  scalar(node, si, stack) {
    const v = this.evaluate(node, si, stack)
    return Array.isArray(v) ? (v[0]?.[0] ?? null) : v
  }

  binary(node, si, stack) {
    const left = this.evaluate(node.left, si, stack)
    const right = this.evaluate(node.right, si, stack)
    // ranges in arithmetic work cell by cell, e.g. SUMPRODUCT((B2:B9="Pune")*(C2:C9))
    if (Array.isArray(left) || Array.isArray(right)) {
      const rows = Math.max(Array.isArray(left) ? left.length : 1, Array.isArray(right) ? right.length : 1)
      const cols = Math.max(Array.isArray(left) ? left[0]?.length || 1 : 1, Array.isArray(right) ? right[0]?.length || 1 : 1)
      const at = (v, r, c) => (Array.isArray(v) ? (v[r % v.length]?.[c % (v[0]?.length || 1)] ?? null) : v)
      return Array.from({ length: rows }, (_, r) => Array.from({ length: cols }, (_, c) => this.operate(node.op, at(left, r, c), at(right, r, c))))
    }
    return this.operate(node.op, left, right)
  }

  operate(op, a, b) {
    if (isError(a)) return a
    if (isError(b)) return b
    const node = { op }
    // dates: date - date = days between, date ± days = a date (like Excel)
    if ((op === "+" || op === "-") && (isDate(a) || isDate(b))) {
      if (op === "-" && isDate(a) && isDate(b)) return dateSerial(a) - dateSerial(b)
      const x = toNumber(a), y = toNumber(b)
      if (isError(x)) return x
      if (isError(y)) return y
      if (op === "-" && isDate(b)) return x - y
      return serialDate(op === "+" ? x + y : x - y)
    }
    switch (node.op) {
      case "&": return toText(a) + toText(b)
      case "=": case "<>": case "<": case ">": case "<=": case ">=": {
        const cmp = compare(a, b)
        return { "=": cmp === 0, "<>": cmp !== 0, "<": cmp < 0, ">": cmp > 0, "<=": cmp <= 0, ">=": cmp >= 0 }[node.op]
      }
    }
    const x = toNumber(a), y = toNumber(b)
    if (isError(x)) return x
    if (isError(y)) return y
    switch (node.op) {
      case "+": return x + y
      case "-": return x - y
      case "*": return x * y
      case "/": return y === 0 ? err("#DIV/0!") : x / y
      case "^": return Math.pow(x, y)
    }
    return err("#ERROR!")
  }

  call(node, si, stack) {
    const name = node.name.replace(/^_XLFN\./, "")
    if (LAZY.has(name)) return this.lazy(name, node.args, si, stack)
    const args = node.args.map((a) => this.evaluate(a, si, stack))
    const fn = EXTRA[name] || this.resolve(name) || BASIC[name]
    if (!fn) return err("#NAME?")
    try {
      let out = fn(...args.map(unwrapForFormulajs))
      // some functions want a plain list of numbers instead of a table (RANK, STDEV, MODE…)
      if (out instanceof Error && args.some(Array.isArray)) {
        const flat = fn(...args.map((a) => (Array.isArray(a) ? unwrapForFormulajs(a).flat() : unwrapForFormulajs(a))))
        if (!(flat instanceof Error)) out = flat
      }
      if (out instanceof Error) return err(errorCode(out))
      if (out instanceof Date) return excelDate(out)
      if (typeof out === "number" && !Number.isFinite(out)) return err("#NUM!")
      return out === undefined ? null : out
    } catch (e) {
      return err(errorCode(e))
    }
  }

  // "STDEV.S" -> STDEV.S / STDEVS; old names like RANK / STDEV / MODE -> RANK.EQ / STDEV.S / MODE.SNGL
  resolve(name) {
    let fn = this.fns[name] ?? this.fns[name.replace(/\./g, "")]
    if (!fn && name.includes(".")) { const [ a, b ] = name.split("."); fn = this.fns[a]?.[b] }
    if (fn && typeof fn === "object") fn = fn.EQ || fn.S || fn.SNGL || fn.INC || fn.MATH || fn.PRECISE || Object.values(fn).find((v) => typeof v === "function")
    return typeof fn === "function" ? fn : null
  }

  lazy(name, args, si, stack) {
    const val = (i) => this.scalar(args[i] ?? { k: "lit", v: null }, si, stack)
    const truthy = (v) => (typeof v === "string" ? v.length > 0 && v.toUpperCase() !== "FALSE" : !!toNumber(v))
    switch (name) {
      case "IF": {
        const cond = val(0)
        if (isError(cond)) return cond
        return truthy(cond) ? (args[1] ? val(1) : true) : (args[2] ? val(2) : false)
      }
      case "IFERROR": { const v = val(0); return isError(v) ? val(1) : v }
      case "IFNA": { const v = val(0); return isError(v) && errorCode(v) === "#N/A" ? val(1) : v }
      case "IFS": {
        for (let i = 0; i + 1 < args.length; i += 2) { const c = val(i); if (isError(c)) return c; if (truthy(c)) return val(i + 1) }
        return err("#N/A")
      }
      case "AND": case "OR": {
        const flat = args.flatMap((a) => { const v = this.evaluate(a, si, stack); return Array.isArray(v) ? v.flat().filter((x) => x !== null && x !== "") : [ v ] })
        const bad = flat.find(isError)
        if (bad) return bad
        return name === "AND" ? flat.every(truthy) : flat.some(truthy)
      }
    }
  }
}

function compare(a, b) {
  const na = typeof a === "number" || a === null, nb = typeof b === "number" || b === null
  if (na && nb) return (a ?? 0) - (b ?? 0)
  const sa = toText(a).toLowerCase(), sb = toText(b).toLowerCase()
  return sa < sb ? -1 : sa > sb ? 1 : 0
}

// formula.js wants plain values: errors as Error objects, empty cells as null
function unwrapForFormulajs(v) {
  if (Array.isArray(v)) return v.map((row) => row.map(unwrapForFormulajs))
  if (v instanceof CellError) { const e = new Error(v.code); e.name = v.code; return e }
  return v
}

// Excel stores dates as day numbers; show them like the rest of the sheet (yyyy-mm-dd)
function excelDate(d) {
  const pad = (n) => String(n).padStart(2, "0")
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
}

const sameValue = (a, b) => (typeof a === "string" && typeof b === "string" ? a.toLowerCase() === b.toLowerCase() : a == b) // eslint-disable-line eqeqeq
const EXTRA = {
  // XLOOKUP(lookup, lookup_array, return_array, [if_not_found], [match_mode 0 exact / -1 next smaller / 1 next larger])
  XLOOKUP: (key, look, ret, notFound, mode = 0) => {
    const list = Array.isArray(look) ? look.flat() : [ look ]
    let i = list.findIndex((v) => sameValue(v, key))
    if (i < 0 && mode && typeof key === "number") {
      let best = -1
      list.forEach((v, j) => { if (typeof v === "number" && (mode < 0 ? v <= key : v >= key) && (best < 0 || (mode < 0 ? v > list[best] : v < list[best]))) best = j })
      i = best
    }
    if (i < 0) return notFound !== undefined && notFound !== null ? notFound : new Error("#N/A")
    if (!Array.isArray(ret)) return ret
    const byRow = Array.isArray(look) && look.length > 1
    return byRow ? ret[i]?.[0] ?? null : ret[0]?.[i] ?? null
  }
}

// Works even if formula.js can't load (offline): the most used functions.
const nums = (args) => args.flat(Infinity).filter((v) => typeof v === "number")
const BASIC = {
  SUM: (...a) => nums(a).reduce((s, v) => s + v, 0),
  AVERAGE: (...a) => { const n = nums(a); return n.length ? n.reduce((s, v) => s + v, 0) / n.length : err("#DIV/0!") },
  MIN: (...a) => { const n = nums(a); return n.length ? Math.min(...n) : 0 },
  MAX: (...a) => { const n = nums(a); return n.length ? Math.max(...n) : 0 },
  COUNT: (...a) => nums(a).length,
  COUNTA: (...a) => a.flat(Infinity).filter((v) => v !== null && v !== "").length,
  ROUND: (v, d = 0) => { const f = 10 ** d; return Math.round(toNumber(v) * f) / f },
  ABS: (v) => Math.abs(toNumber(v)),
  CONCATENATE: (...a) => a.flat(Infinity).map(toText).join(""),
  CONCAT: (...a) => a.flat(Infinity).map(toText).join(""),
  UPPER: (v) => toText(v).toUpperCase(),
  LOWER: (v) => toText(v).toLowerCase(),
  LEN: (v) => toText(v).length,
  TRIM: (v) => toText(v).trim().replace(/\s+/g, " ")
}

// For the "Functions" help list
export const COMMON_FUNCTIONS = [
  [ "SUM(A2:A10)", "Total" ], [ "AVERAGE(A2:A10)", "Average" ], [ "COUNT / COUNTA(range)", "Count numbers / filled cells" ],
  [ "MIN / MAX(range)", "Smallest / largest" ], [ "ROUND(value, 2)", "Round" ], [ "IF(test, yes, no)", "Condition" ],
  [ "IFERROR(value, alt)", "Fallback on error" ], [ "VLOOKUP(key, table, col, FALSE)", "Look up in a table" ],
  [ "XLOOKUP / INDEX / MATCH", "Look up" ], [ "SUMIF(range, criteria, sum_range)", "Total with a condition" ],
  [ "SUMIFS / COUNTIF / COUNTIFS / AVERAGEIF", "Totals / counts with conditions" ], [ "SUMPRODUCT(a, b)", "Sum of products" ],
  [ "CONCAT / LEFT / RIGHT / MID / LEN / UPPER / TRIM", "Text" ], [ "TODAY() / DATE / YEAR / MONTH / DAY", "Dates" ]
]

// ---- inserting / deleting rows or columns (references follow, like Excel) ----
// axis "row" | "col"; `at` is the first row / column index; count > 0 inserts, < 0 deletes.
// `target` is the sheet being changed, `home` the sheet this formula lives on.
export function adjustReferences(text, { axis, at, count, target, home }) {
  if (typeof text !== "string" || !text.startsWith("=")) return text
  const same = (tk) => String(tk.sheet ?? home).toLowerCase() === String(target).toLowerCase()
  const del = count < 0 ? -count : 0
  const move = (i, end = null) => {
    if (count > 0) return i >= at ? i + count : i
    if (i >= at && i < at + del) return end === null ? null : end ? at - 1 : at // a deleted end of a range shrinks it
    return i >= at + del ? i - del : i
  }
  const tokens = tokenize(text.slice(1))
  const out = []
  for (let i = 0; i < tokens.length; i++) {
    const tk = tokens[i]
    if (tk.t === "ref" && same(tk)) {
      const pair = tokens[i + 1]?.t === "op" && tokens[i + 1].v === ":" && tokens[i + 2]?.t === "ref" ? tokens[i + 2] : null
      if (pair) {
        const a = { ...tk }, b = { ...pair }
        const key = axis === "row" ? "row" : "col"
        a[key] = move(tk[key], false)
        b[key] = move(pair[key], true)
        if (a[key] === null || b[key] === null || b[key] < a[key]) out.push("#REF!")
        else out.push(refText(a), ":", refText({ ...b, sheetRaw: "" }))
        i += 2
        continue
      }
      const moved = { ...tk }
      const key = axis === "row" ? "row" : "col"
      moved[key] = move(tk[key])
      out.push(moved[key] === null ? "#REF!" : refText(moved))
      continue
    }
    if (tk.t === "colrange" && same(tk) && axis === "col") {
      const a = move(tk.a.col, false), b = move(tk.b.col, true)
      out.push(a === null || b === null || b < a ? "#REF!" : `${tk.sheetRaw}${tk.a.abs ? "$" : ""}${colName(a)}:${tk.b.abs ? "$" : ""}${colName(b)}`)
      continue
    }
    out.push(tk.t === "ref" ? refText(tk) : tk.t === "colrange" ? `${tk.sheetRaw}${tk.a.abs ? "$" : ""}${colName(tk.a.col)}:${tk.b.abs ? "$" : ""}${colName(tk.b.col)}` : (tk.raw ?? tk.v))
  }
  return "=" + out.join("")
}

function refText(tk) {
  return `${tk.sheetRaw || ""}${tk.absC ? "$" : ""}${colName(tk.col)}${tk.absR ? "$" : ""}${tk.row + 1}`
}

// Number formats of the Home ribbon, shown like Excel (Indian grouping)
export function formatValue(v, style = {}) {
  if (typeof v !== "number" || !style.fmt || style.fmt === "general") return null
  const fallback = { number: 2, currency: 2, percent: 0, comma: 0 }[style.fmt] ?? 2
  const d = Number.isInteger(style.d) ? style.d : fallback
  const n = style.fmt === "percent" ? v * 100 : v
  const text = new Intl.NumberFormat("en-IN", { minimumFractionDigits: d, maximumFractionDigits: d, useGrouping: style.fmt !== "number" || true }).format(n)
  if (style.fmt === "currency") return `₹${text}`
  if (style.fmt === "percent") return `${text}%`
  return text
}
