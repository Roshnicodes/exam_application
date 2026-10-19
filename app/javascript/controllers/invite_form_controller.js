import { Controller } from "@hotwired/stimulus"

// Invite form: "Online test only" hides everything about interviews (resume, interview details, panel)
// and the page title / button say what the invite is for.
export default class extends Controller {
  static targets = [ "interviewOnly", "submitLabel" ]

  connect() {
    this.planChanged()
  }

  planChanged() {
    const plan = this.element.querySelector("input[name='invitation[interview_plan]']:checked")?.value
    const testOnly = plan === "none"
    this.interviewOnlyTargets.forEach((el) => {
      el.hidden = testOnly
      // hidden fields are not sent, so a test-only invite doesn't carry interview details
      el.querySelectorAll("input, select, textarea").forEach((input) => { input.disabled = testOnly })
    })
    const editing = this.element.querySelector("input[name='_method']")
    if (!editing) {
      const title = document.querySelector(".page-hero h1")
      if (title) title.textContent = testOnly ? "Invite for online test" : "Invite for test + interview"
      if (this.hasSubmitLabelTarget) this.submitLabelTarget.textContent = testOnly ? "Create test link" : "Create test link & interview plan"
    }
  }
}
