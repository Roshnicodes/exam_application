import { Controller } from "@hotwired/stimulus"

// Invite forms (single + bulk). The plan decides which parts of the form matter:
//   "none"      — online test only: everything about interviews is hidden
//   "practical" — practical assessment only: the question paper is hidden, the assessment is required
//   others      — test + interview rounds (a practical assessment can be added too)
export default class extends Controller {
  static targets = [ "interviewOnly", "testOnly", "assessmentPart", "assessmentSelect", "assessmentHint", "submitLabel" ]
  static values = {
    testTitle: { type: String, default: "Invite for online test" },
    interviewTitle: { type: String, default: "Invite for test + interview" },
    practicalTitle: { type: String, default: "Invite for practical assessment" },
    testButton: { type: String, default: "Create test link" },
    interviewButton: { type: String, default: "Create test link & interview plan" },
    practicalButton: { type: String, default: "Create assessment link" }
  }

  connect() {
    this.planChanged()
  }

  planChanged() {
    const plan = this.element.querySelector("input[name$='[interview_plan]']:checked")?.value
    const testOnly = plan === "none"
    const practical = plan === "practical"
    this.element.classList.toggle("test-only", testOnly)
    this.element.classList.toggle("practical-only", practical)

    // hidden fields are not sent, so a test-only invite doesn't carry interview details
    this.toggle(this.interviewOnlyTargets, testOnly || practical)
    this.toggle(this.testOnlyTargets, practical)

    this.assessmentPartTargets.forEach((el) => { el.hidden = false })
    if (this.hasAssessmentSelectTarget) {
      this.assessmentSelectTarget.required = practical
      this.assessmentSelectTarget.closest(".field")?.classList.toggle("is-required", practical)
    }
    if (this.hasAssessmentHintTarget) {
      this.assessmentHintTarget.textContent = practical
        ? "Required — this is the whole test for this candidate."
        : "Optional — adds a practical assessment round after the online test."
    }

    const editing = this.element.querySelector("input[name='_method']")
    if (!editing) {
      const title = document.querySelector(".page-hero h1")
      const label = practical ? "practical" : testOnly ? "test" : "interview"
      if (title) title.textContent = this[`${label}TitleValue`]
      if (this.hasSubmitLabelTarget) this.submitLabelTarget.textContent = this[`${label}ButtonValue`]
    }
  }

  toggle(elements, off) {
    elements.forEach((el) => {
      el.hidden = off
      el.querySelectorAll("input, select, textarea").forEach((input) => { input.disabled = off })
    })
  }
}
