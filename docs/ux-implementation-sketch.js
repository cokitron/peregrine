// ============================================================
// IMPLEMENTATION SKETCH — New workflow_editor_controller.js
// This is a reference for how the improved UX would be structured.
// Not meant to be dropped in as-is — it's a design document.
// ============================================================

import { Controller } from "@hotwired/stimulus"

const NODE_TYPES = {
  kiro:  { label: "Kiro AI",  color: "kreoz-green", icon: "⚡", fields: ["prompt"] },
  shell: { label: "Shell",    color: "kreoz-amber",  icon: "▶",  fields: ["command"] },
  ruby:  { label: "Ruby",     color: "kreoz-purple", icon: "◆",  fields: ["code"] },
  gate:  { label: "Gate",     color: "kreoz-red",    icon: "◇",  fields: ["condition"] },
}

const COLOR_MAP = {
  "kreoz-green":  { border: "border-l-kreoz-green",  bg: "bg-kreoz-green",  pill: "bg-kreoz-green/10 text-kreoz-green" },
  "kreoz-amber":  { border: "border-l-kreoz-amber",  bg: "bg-kreoz-amber",  pill: "bg-kreoz-amber/10 text-kreoz-amber-dark" },
  "kreoz-purple": { border: "border-l-kreoz-purple", bg: "bg-kreoz-purple", pill: "bg-kreoz-purple/10 text-kreoz-purple" },
  "kreoz-red":    { border: "border-l-kreoz-red",    bg: "bg-kreoz-red",    pill: "bg-kreoz-red/10 text-kreoz-red" },
}

const MAX_HISTORY = 30

export default class extends Controller {
  static targets = ["steps", "nombre", "defaultAgent"]
  static values  = { updateUrl: String, steps: Array, agents: Array, nodeStates: Object }

  // ── Lifecycle ──────────────────────────────────────────────

  connect() {
    this.expandedIndex = null  // only one card expanded at a time
    this.history = [structuredClone(this.stepsValue)]
    this.historyIndex = 0
    this.dragIndex = null
    this.render()
    this.bindKeyboard()
  }

  disconnect() {
    document.removeEventListener("keydown", this._keyHandler)
  }

  // ── Rendering ──────────────────────────────────────────────

  render() {
    const container = this.stepsTarget
    container.innerHTML = ""

    this.stepsValue.forEach((step, i) => {
      if (i === this.expandedIndex) {
        container.appendChild(this.buildExpandedCard(step, i))
      } else {
        container.appendChild(this.buildCollapsedCard(step, i))
      }
      if (i < this.stepsValue.length - 1) {
        container.appendChild(this.buildConnector(i))
      }
    })
  }

  // ── Collapsed Card ─────────────────────────────────────────

  buildCollapsedCard(step, index) {
    const type = NODE_TYPES[step.type] || NODE_TYPES.kiro
    const colors = COLOR_MAP[type.color]
    const status = this.getStepStatus(step.name)
    const deps = this.parseDeps(step)
    const disabled = step.disabled ? "opacity-50" : ""

    const card = document.createElement("div")
    card.className = `flex items-center gap-3 px-4 py-3 bg-white border border-borde rounded-lg shadow-sm cursor-pointer hover:border-kreoz-green hover:shadow-md transition-all duration-150 border-l-4 ${colors.border} ${disabled}`
    card.dataset.index = index
    card.setAttribute("draggable", "false") // only handle drags

    card.innerHTML = `
      <button class="drag-handle cursor-grab active:cursor-grabbing text-gris-claro hover:text-gris"
              draggable="true"
              data-action="dragstart->workflow-editor#dragStart dragend->workflow-editor#dragEnd">
        <svg class="w-4 h-4" viewBox="0 0 16 16" fill="currentColor">
          <circle cx="5" cy="3" r="1.5"/><circle cx="11" cy="3" r="1.5"/>
          <circle cx="5" cy="8" r="1.5"/><circle cx="11" cy="8" r="1.5"/>
          <circle cx="5" cy="13" r="1.5"/><circle cx="11" cy="13" r="1.5"/>
        </svg>
      </button>

      <span class="text-lg">${type.icon}</span>

      <span class="font-semibold text-sm text-grafito truncate flex-1 ${step.disabled ? 'line-through' : ''}"
            data-action="click->workflow-editor#expand" data-index="${index}">
        ${step.name || `${type.label} #${index + 1}`}
      </span>

      <span class="px-2 py-0.5 rounded text-xs font-medium ${colors.pill}">${type.label}</span>

      ${deps.map(d => `<span class="px-1.5 py-0.5 rounded text-xs bg-gray-100 text-gris">← ${d}</span>`).join("")}

      ${this.statusDot(status)}

      <div class="relative">
        <button class="text-gris hover:text-grafito p-1" data-action="click->workflow-editor#toggleMenu" data-index="${index}">⋮</button>
      </div>
    `

    // Click to expand (but not on handle or menu)
    card.addEventListener("click", (e) => {
      if (e.target.closest(".drag-handle") || e.target.closest("[data-action*=toggleMenu]")) return
      this.expandedIndex = index
      this.render()
    })

    return card
  }

  // ── Expanded Card ──────────────────────────────────────────

  buildExpandedCard(step, index) {
    const type = NODE_TYPES[step.type] || NODE_TYPES.kiro
    const colors = COLOR_MAP[type.color]
    const availableRefs = this.getAvailableRefs(index)

    const card = document.createElement("div")
    card.className = `bg-white border border-kreoz-green rounded-lg shadow-md border-l-4 ${colors.border} w-full max-w-lg`

    card.innerHTML = `
      <div class="${colors.bg} text-white px-4 py-2 flex items-center justify-between rounded-t-lg">
        <span class="font-semibold text-sm">${type.icon} ${type.label}</span>
        <div class="flex items-center gap-2">
          <span class="text-xs opacity-75">#${index + 1}</span>
          <button data-action="click->workflow-editor#collapse" class="text-white/70 hover:text-white">
            <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 15l-6-6-6 6"/></svg>
          </button>
        </div>
      </div>

      <div class="p-4 space-y-3">
        <div>
          <label class="block text-xs font-medium text-gris uppercase tracking-wide mb-1">Nombre</label>
          <input type="text" value="${step.name || ''}"
                 data-action="input->workflow-editor#updateField"
                 data-index="${index}" data-field="name"
                 class="w-full border border-borde rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-kreoz-green" />
        </div>

        ${this.buildConfigFields(step, index)}

        ${availableRefs.length > 0 ? `
          <div class="pt-2 border-t border-borde">
            <span class="text-xs text-gris">Refs disponibles: </span>
            ${availableRefs.map(r => `<button class="text-xs text-kreoz-green hover:underline mr-1" data-action="click->workflow-editor#insertRef" data-ref="${r}" data-index="${index}">{{${r}}}</button>`).join("")}
          </div>
        ` : ""}
      </div>
    `

    return card
  }

  // ── Connector ──────────────────────────────────────────────

  buildConnector(fromIndex) {
    const el = document.createElement("div")
    const nextStatus = this.getStepStatus(this.stepsValue[fromIndex + 1]?.name)
    const isRunning = nextStatus === "running"

    el.className = "flex justify-center py-1"
    el.innerHTML = `
      <div class="w-0.5 h-6 bg-borde relative ${isRunning ? 'overflow-hidden' : ''}">
        ${isRunning ? '<div class="absolute w-1.5 h-1.5 bg-blue-500 rounded-full animate-bounce left-[-2px]"></div>' : ''}
      </div>
    `
    // Drop zone for drag-and-drop
    el.dataset.dropIndex = fromIndex + 1
    el.addEventListener("dragover", (e) => { e.preventDefault(); el.classList.add("scale-y-150") })
    el.addEventListener("dragleave", () => el.classList.remove("scale-y-150"))
    el.addEventListener("drop", (e) => { e.preventDefault(); this.dropAt(fromIndex + 1) })

    return el
  }

  // ── Drag and Drop ──────────────────────────────────────────

  dragStart(event) {
    const card = event.target.closest("[data-index]")
    this.dragIndex = parseInt(card.dataset.index)
    card.classList.add("opacity-40", "scale-[0.98]")
    event.dataTransfer.effectAllowed = "move"
  }

  dragEnd(event) {
    this.dragIndex = null
    this.render() // clean up visual state
  }

  dropAt(targetIndex) {
    if (this.dragIndex === null || this.dragIndex === targetIndex) return
    const steps = [...this.stepsValue]
    const [moved] = steps.splice(this.dragIndex, 1)
    const insertAt = targetIndex > this.dragIndex ? targetIndex - 1 : targetIndex
    steps.splice(insertAt, 0, moved)
    this.pushHistory()
    this.stepsValue = steps
    this.expandedIndex = null
    this.render()
    this.autoSave()
  }

  // ── Undo / Redo ────────────────────────────────────────────

  pushHistory() {
    // Trim future states if we're in the middle of history
    this.history = this.history.slice(0, this.historyIndex + 1)
    this.history.push(structuredClone(this.stepsValue))
    if (this.history.length > MAX_HISTORY) this.history.shift()
    this.historyIndex = this.history.length - 1
  }

  undo() {
    if (this.historyIndex <= 0) return
    this.historyIndex--
    this.stepsValue = structuredClone(this.history[this.historyIndex])
    this.expandedIndex = null
    this.render()
    this.autoSave()
    this.showToast("Deshecho")
  }

  redo() {
    if (this.historyIndex >= this.history.length - 1) return
    this.historyIndex++
    this.stepsValue = structuredClone(this.history[this.historyIndex])
    this.expandedIndex = null
    this.render()
    this.autoSave()
    this.showToast("Rehecho")
  }

  // ── Keyboard Shortcuts ─────────────────────────────────────

  bindKeyboard() {
    this._keyHandler = (e) => {
      // Don't capture when typing in inputs
      if (e.target.matches("input, textarea, select")) {
        if (e.key === "Escape") { this.collapse(); e.preventDefault() }
        return
      }

      if (e.ctrlKey || e.metaKey) {
        if (e.key === "z" && !e.shiftKey) { this.undo(); e.preventDefault() }
        if (e.key === "z" && e.shiftKey)  { this.redo(); e.preventDefault() }
        if (e.key === "Z")                { this.redo(); e.preventDefault() }
        if (e.key === "d") { this.duplicateSelected(); e.preventDefault() }
        if (e.key === "ArrowUp")   { this.moveSelected(-1); e.preventDefault() }
        if (e.key === "ArrowDown") { this.moveSelected(1); e.preventDefault() }
      }

      if (e.key === "Delete" || e.key === "Backspace") {
        if (this.expandedIndex !== null) { this.removeStep(this.expandedIndex); e.preventDefault() }
      }
      if (e.key === "Escape") { this.collapse(); e.preventDefault() }
    }
    document.addEventListener("keydown", this._keyHandler)
  }

  // ── Actions ────────────────────────────────────────────────

  expand(event) {
    this.expandedIndex = parseInt(event.currentTarget.dataset.index)
    this.render()
  }

  collapse() {
    this.expandedIndex = null
    this.render()
  }

  duplicateSelected() {
    const idx = this.expandedIndex ?? this.stepsValue.length - 1
    if (idx < 0) return
    this.pushHistory()
    const steps = [...this.stepsValue]
    const clone = { ...steps[idx], name: `${steps[idx].name}_copy` }
    steps.splice(idx + 1, 0, clone)
    this.stepsValue = steps
    this.expandedIndex = idx + 1
    this.render()
    this.autoSave()
  }

  toggleDisabled(index) {
    this.pushHistory()
    const steps = [...this.stepsValue]
    steps[index] = { ...steps[index], disabled: !steps[index].disabled }
    this.stepsValue = steps
    this.render()
    this.autoSave()
  }

  removeStep(index) {
    this.pushHistory()
    const steps = [...this.stepsValue]
    steps.splice(index, 1)
    this.stepsValue = steps
    this.expandedIndex = null
    this.render()
    this.autoSave()
    this.showToast("Paso eliminado", "Deshacer", () => this.undo())
  }

  moveSelected(direction) {
    const idx = this.expandedIndex
    if (idx === null) return
    const newIdx = idx + direction
    if (newIdx < 0 || newIdx >= this.stepsValue.length) return
    this.pushHistory()
    const steps = [...this.stepsValue]
    ;[steps[idx], steps[newIdx]] = [steps[newIdx], steps[idx]]
    this.stepsValue = steps
    this.expandedIndex = newIdx
    this.render()
    this.autoSave()
  }

  // ── Helpers ────────────────────────────────────────────────

  parseDeps(step) {
    const text = [step.prompt, step.command, step.code, step.condition].filter(Boolean).join(" ")
    const matches = text.match(/\{\{(\w+)\}\}/g) || []
    return [...new Set(matches.map(m => m.replace(/[{}]/g, "")))]
  }

  getAvailableRefs(index) {
    return ["input", ...this.stepsValue.slice(0, index).map(s => s.name).filter(Boolean)]
  }

  getStepStatus(name) {
    return this.nodeStatesValue?.[name] || "idle"
  }

  statusDot(status) {
    const dots = {
      idle:      '<span class="w-2.5 h-2.5 rounded-full bg-gray-200"></span>',
      queued:    '<span class="w-2.5 h-2.5 rounded-full border-2 border-gray-300"></span>',
      running:   '<span class="w-2.5 h-2.5 rounded-full bg-blue-500 animate-pulse"></span>',
      completed: '<span class="w-2.5 h-2.5 rounded-full bg-kreoz-green"></span>',
      failed:    '<span class="w-2.5 h-2.5 rounded-full bg-kreoz-red"></span>',
      skipped:   '<span class="w-2.5 h-2.5 text-gris text-xs">—</span>',
    }
    return dots[status] || dots.idle
  }

  showToast(message, actionLabel, actionFn) {
    // Minimal toast — bottom-center, auto-dismiss 3s
    const toast = document.createElement("div")
    toast.className = "fixed bottom-6 left-1/2 -translate-x-1/2 bg-grafito text-white px-4 py-2 rounded-lg shadow-lg text-sm flex items-center gap-3 z-50 animate-fade-in"
    toast.innerHTML = `
      <span>${message}</span>
      ${actionLabel ? `<button class="text-kreoz-green font-semibold hover:underline">${actionLabel}</button>` : ""}
    `
    if (actionFn) toast.querySelector("button").addEventListener("click", () => { actionFn(); toast.remove() })
    document.body.appendChild(toast)
    setTimeout(() => toast.remove(), 3000)
  }

  // ... (addStep, updateField, autoSave, save — same as current, with pushHistory() calls added)
}
