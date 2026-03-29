import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["textarea", "counter", "form", "label"]

  open(event) {
    const { notes, url, workoutLabel } = event.currentTarget.dataset

    this.formTarget.action = url
    this.textareaTarget.value = notes || ""
    this.labelTarget.textContent = workoutLabel || ""
    this.updateCounter()

    this.#modal.open()
  }

  updateCounter() {
    const remaining = 280 - this.textareaTarget.value.length
    this.counterTarget.textContent = `${remaining} characters remaining`
  }

  get #modal() {
    return this.application.getControllerForElementAndIdentifier(this.element, "modal")
  }
}
