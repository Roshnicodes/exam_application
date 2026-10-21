import { Controller } from "@hotwired/stimulus"

// Live monitor search box: hides the tiles whose text doesn't match.
export default class extends Controller {
  filter() {
    const q = this.element.value.trim().toLowerCase()
    document.querySelectorAll(".mon-grid > .mon-tile").forEach((tile) => {
      tile.hidden = q !== "" && !tile.textContent.toLowerCase().includes(q)
    })
  }
}
