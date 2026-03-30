import { Controller } from "@hotwired/stimulus"

// Auto-refreshes the page while there are pending estimates.
// Usage: data-controller="auto-refresh" on a container element.
// Refreshes every 2 seconds until the element is removed from the DOM
// (i.e., all estimates are complete and the page no longer renders this controller).
export default class extends Controller {
  connect() {
    this.timer = setTimeout(() => {
      window.location.reload()
    }, 2000)
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer)
  }
}
