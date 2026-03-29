import { Controller } from "@hotwired/stimulus"

// Generic reusable modal controller for <dialog> elements.
// Usage: wrap a <dialog> with data-controller="modal" and
// use data-action="modal#open" / data-action="modal#close" on triggers.
// Clicking the backdrop (outside the dialog content) closes the modal.
export default class extends Controller {
  static targets = ["dialog"]

  open() {
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  clickOutside(event) {
    if (event.target === this.dialogTarget) {
      this.close()
    }
  }
}
