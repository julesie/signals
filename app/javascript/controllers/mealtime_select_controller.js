import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["frame"]
  static values = { url: String }

  change(event) {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("mealtime", event.target.value)
    this.frameTarget.src = url.toString()
  }
}
