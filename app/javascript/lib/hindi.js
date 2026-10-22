// English → Hindi for the question paper in the candidate's browser. No API key, no setup:
// 1. Chrome's built-in translator when its Hindi pack is already on the computer (works offline)
// 2. otherwise Google Translate over the internet (any browser, phones too)
// 3. last resort: Chrome's built-in translator after downloading the pack (needs a click)

const PAIR = { sourceLanguage: "en", targetLanguage: "hi" }
const cache = new Map()
let translatorPromise = null

export function hindiSupported() {
  return true // Google Translate works in every browser while online
}

function chromeTranslatorExists() {
  return "Translator" in self
}

// availability() can hang in some browsers: give up after a few seconds
function chromeAvailability() {
  if (!chromeTranslatorExists()) return Promise.resolve("unavailable")
  return Promise.race([
    self.Translator.availability(PAIR).catch(() => "unavailable"),
    new Promise((resolve) => setTimeout(() => resolve("unavailable"), 4000))
  ])
}

const google = {
  async translate(text) {
    const url = `https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=hi&dt=t&q=${encodeURIComponent(text)}`
    const res = await fetch(url, { credentials: "omit" })
    if (!res.ok) throw new Error(`translate ${res.status}`)
    const data = await res.json()
    return (data?.[0] || []).map((part) => part?.[0] || "").join("")
  }
}

export function hindiTranslator(onProgress, fromClick = false) {
  translatorPromise ||= (async () => {
    if ((await chromeAvailability()) === "available") return self.Translator.create(PAIR)
    try {
      if ((await google.translate("Hello")).trim()) return google
    } catch {}
    if (fromClick && chromeTranslatorExists()) {
      return self.Translator.create({
        ...PAIR,
        monitor(m) { m.addEventListener("downloadprogress", (e) => onProgress?.(Math.round(e.loaded * 100))) }
      })
    }
    throw new Error("unavailable")
  })()
  translatorPromise.catch(() => { translatorPromise = null })
  return translatorPromise
}

// Translation can start without a click (Google, or Chrome's pack already there)
export async function hindiReady() {
  try { await hindiTranslator(); return true } catch { return false }
}

async function translateCell(translator, text) {
  const t = text.trim()
  if (!t || !/[A-Za-z]/.test(t)) return text // numbers, symbols, formulas stay as they are
  if (looksLikeCode(t)) return text // `map`, `each_slice`, `arr.select { }`, `display: grid` stay as written
  if (cache.has(t)) return cache.get(t)
  try {
    const out = (await translator.translate(t)) || text
    cache.set(t, out)
    return out
  } catch { return text }
}

function looksLikeCode(t) {
  if (/^[a-z_$][\w$?!]*$/.test(t)) return true // a single lowercase identifier: map, each, inject
  if (t.split(/\s+/).length > 5) return false // a sentence: translate it even if it mentions x = 5
  return /[{}<>;=]|=>|::|\w\.\w+\(|\w\(\)|^[\w-]+:\s*[\w-]+;?$/.test(t)
}

// Translates the text inside an element (a question with tables etc.) into a copy of it.
export async function translateElement(translator, element) {
  const copy = element.cloneNode(true)
  const walker = document.createTreeWalker(copy, NodeFilter.SHOW_TEXT)
  const nodes = []
  while (walker.nextNode()) if (/[A-Za-z]/.test(walker.currentNode.nodeValue)) nodes.push(walker.currentNode)
  await Promise.all(nodes.map(async (node) => {
    const lead = node.nodeValue.match(/^\s*/)[0]
    const tail = node.nodeValue.match(/\s*$/)[0]
    node.nodeValue = lead + (await translateCell(translator, node.nodeValue)).trim() + tail
  }))
  return copy
}
