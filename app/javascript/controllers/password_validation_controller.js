import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "feedback"]

  validate() {
    const pw = this.inputTarget.value
    const checks = []
    if (pw.length < 8) checks.push("mínimo 8 caracteres")
    if (!/[A-Z]/.test(pw)) checks.push("1 mayúscula")
    if (!/\d/.test(pw)) checks.push("1 número")

    if (checks.length === 0) {
      this.feedbackTarget.textContent = "✓ Contraseña válida"
      this.feedbackTarget.className = "text-sm mt-1 text-green-600"
    } else {
      this.feedbackTarget.textContent = `Falta: ${checks.join(", ")}`
      this.feedbackTarget.className = "text-sm mt-1 text-red-500"
    }
  }
}
