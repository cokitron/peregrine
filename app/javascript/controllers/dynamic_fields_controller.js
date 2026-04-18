import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "template"]

  add() {
    const clone = this.templateTarget.cloneNode(true)
    clone.querySelectorAll("input").forEach(input => input.value = "")
    this.containerTarget.appendChild(clone)
  }
}
