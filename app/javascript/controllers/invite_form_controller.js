import { Controller } from "@hotwired/stimulus"

// Invite forms (single + bulk): "Online test only" hides everything about interviews
// (resume, experience, interview details, panel) and the page title / button say what the invite is for.
export default class extends Controller {
  static targets = [ "interviewOnly", "submitLabel" ]
  static values = {
    testTitle: { type: String, default: "Invite for online test" },
    interviewTitle: { type: String, default: "Invite for test + interview" },
    testButton: { type: String, default: "Create test link" },
    interviewButton: { type: String, default: "Create test link & interview plan" }
  }

  connect() {
    this.planChanged()
  }

  planChanged() {
    const plan = this.element.querySelector("input[name$='[interview_plan]']:checked")?.value
    const testOnly = plan === "none"
    this.element.classList.toggle("test-only", testOnly)
    this.interviewOnlyTargets.forEach((el) => {
      el.hidden = testOnly
      // hidden fields are not sent, so a test-only invite doesn't carry interview details
      el.querySelectorAll("input, select, textarea").forEach((input) => { input.disabled = testOnly })
    })
    const editing = this.element.querySelector("input[name='_method']")
    if (!editing) {
      const title = document.querySelector(".page-hero h1")
      if (title) title.textContent = testOnly ? this.testTitleValue : this.interviewTitleValue
      if (this.hasSubmitLabelTarget) this.submitLabelTarget.textContent = testOnly ? this.testButtonValue : this.interviewButtonValue
    }
  }
}
