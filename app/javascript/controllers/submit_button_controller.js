import { Controller } from "@hotwired/stimulus"

// Disables the submit button and shows a loading state while the form is submitting.
// Usage: data-controller="submit-button" on the form,
//        data-submit-button-target="button" on the submit input/button,
//        data-submit-button-loading-value="Estimating..." for custom text.
export default class extends Controller {
  static targets = ["button"]
  static values = { loading: { type: String, default: "Estimating..." } }

  connect() {
    this.element.addEventListener("submit", this.disable.bind(this))
  }

  disconnect() {
    this.element.removeEventListener("submit", this.disable.bind(this))
  }

  disable() {
    this.buttonTarget.disabled = true
    this.buttonTarget.value = this.loadingValue
    this.buttonTarget.classList.add("opacity-50", "cursor-wait")
  }
}
