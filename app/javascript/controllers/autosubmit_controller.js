import { Controller } from "@hotwired/stimulus"

// Submits the filter form as soon as a dropdown changes.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
