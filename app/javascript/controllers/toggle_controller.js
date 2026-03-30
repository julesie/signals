import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "icon"]

  toggle() {
    this.contentTargets.forEach(el => el.classList.toggle("hidden"))
    this.iconTargets.forEach(el => el.classList.toggle("rotate-180"))
  }
}
