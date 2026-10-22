// English → Hindi with Chrome's built-in translator (free, runs on the computer, no API key).
// Chrome 138+ on desktop has it; elsewhere `hindiSupported()` is false.

export function hindiSupported() {
  return "Translator" in self
}

let translatorPromise = null

const PAIR = { sourceLanguage: "en", targetLanguage: "hi" }

// availability() can hang in some browsers: give up after a few seconds
function availability() {
  return Promise.race([
    self.Translator.availability(PAIR),
    new Promise((resolve) => setTimeout(() => resolve("unavailable"), 6000))
  ])
}

// Call straight from a click the first time: Chrome downloads the Hindi pack once (needs a click).
export function hindiTranslator(onProgress) {
  if (!hindiSupported()) return Promise.reject(new Error("unsupported"))
  translatorPromise ||= (async () => {
    // create() first, while the click still counts (it starts the one-time download)
    const created = self.Translator.create({
      ...PAIR,
      monitor(m) { m.addEventListener("downloadprogress", (e) => onProgress?.(Math.round(e.loaded * 100))) }
    })
    created.catch(() => {})
    if ((await availability()) === "unavailable") throw new Error("unavailable")
    return created
  })()
  translatorPromise.catch(() => { translatorPromise = null })
  return translatorPromise
}

// Ready without a click? (the pack was downloaded earlier)
export async function hindiReady() {
  if (!hindiSupported()) return false
  try { return (await availability()) === "available" } catch { return false }
}

async function translateCell(translator, text) {
  const t = text.trim()
  if (!t || !/[A-Za-z]/.test(t)) return text // numbers, symbols, formulas stay as they are
  try { return await translator.translate(t) } catch { return text }
}

// Translates the text inside an element (a question with tables etc.) into a copy of it.
export async function translateElement(translator, element) {
  const copy = element.cloneNode(true)
  const walker = document.createTreeWalker(copy, NodeFilter.SHOW_TEXT)
  const nodes = []
  while (walker.nextNode()) nodes.push(walker.currentNode)
  for (const node of nodes) {
    if (/[A-Za-z]/.test(node.nodeValue)) {
      const lead = node.nodeValue.match(/^\s*/)[0]
      const tail = node.nodeValue.match(/\s*$/)[0]
      node.nodeValue = lead + (await translateCell(translator, node.nodeValue)).trim() + tail
    }
  }
  return copy
}
