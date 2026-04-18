import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["nombre", "descripcion", "steering", "contextFiles", "preview"]
  static values  = { updateUrl: String, contextFiles: Array }

  connect() {
    this.renderContextFiles()
    this.renderPreview()
  }

  renderContextFiles() {
    const container = this.contextFilesTarget
    container.innerHTML = ""
    this.contextFilesValue.forEach((path, i) => {
      const row = document.createElement("div")
      row.className = "flex items-center gap-2"
      row.innerHTML = `
        <input type="text" value="${path}" data-index="${i}"
               placeholder="/path/to/file.md"
               class="flex-1 border border-borde rounded-lg px-3 py-2 text-sm font-mono focus:outline-none focus:border-kreoz-green" />
        <button data-index="${i}" class="text-kreoz-red hover:text-kreoz-red-dark p-1">
          <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6L6 18M6 6l12 12"/></svg>
        </button>`
      row.querySelector("input").addEventListener("blur", (e) => {
        const files = [...this.contextFilesValue]
        files[i] = e.target.value
        this.contextFilesValue = files
        this.save()
      })
      row.querySelector("button").addEventListener("click", () => {
        const files = [...this.contextFilesValue]
        files.splice(i, 1)
        this.contextFilesValue = files
        this.renderContextFiles()
        this.save()
      })
      container.appendChild(row)
    })
  }

  addContextFile() {
    this.contextFilesValue = [...this.contextFilesValue, ""]
    this.renderContextFiles()
    // Focus the new input
    const inputs = this.contextFilesTarget.querySelectorAll("input")
    inputs[inputs.length - 1]?.focus()
  }

  async save() {
    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    const resp = await fetch(this.updateUrlValue, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
      body: JSON.stringify({
        agent: {
          nombre: this.nombreTarget.value,
          descripcion: this.descripcionTarget.value,
          steering_document: this.steeringTarget.value,
          context_files: this.contextFilesValue.filter(f => f.trim() !== "")
        }
      })
    })
    if (resp.ok) {
      this.renderPreview()
      const t = document.createElement("div")
      t.className = "fixed bottom-6 left-1/2 -translate-x-1/2 bg-grafito text-white px-4 py-2 rounded-lg shadow-lg text-sm z-50"
      t.textContent = "Saved ✓"
      document.body.appendChild(t)
      setTimeout(() => t.remove(), 2000)
    }
  }

  renderPreview() {
    if (!this.hasPreviewTarget || !this.hasSteeringTarget) return
    this.previewTarget.innerHTML = this.markdownToHtml(this.steeringTarget.value)
  }

  markdownToHtml(md) {
    return md
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/^### (.+)$/gm, '<h3 class="text-sm font-bold text-grafito mt-3 mb-1">$1</h3>')
      .replace(/^## (.+)$/gm, '<h2 class="text-base font-bold text-grafito mt-4 mb-1">$1</h2>')
      .replace(/^# (.+)$/gm, '<h1 class="text-lg font-bold text-grafito mt-4 mb-2">$1</h1>')
      .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.+?)\*/g, '<em>$1</em>')
      .replace(/`(.+?)`/g, '<code class="px-1 py-0.5 bg-fondo-card rounded text-kreoz-green text-xs">$1</code>')
      .replace(/^- (.+)$/gm, '<li class="ml-4 text-sm">• $1</li>')
      .replace(/\n/g, '<br>')
  }
}
