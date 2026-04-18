import { Controller } from "@hotwired/stimulus"

const NODE_TYPES = {
  kiro:     { label: "Kiro AI",   icon: "⚡", fields: ["prompt"],      border: "border-l-kreoz-green", bg: "bg-kreoz-green-dark",  pill: "bg-kreoz-green-light text-kreoz-green" },
  shell:    { label: "Shell",     icon: "▶",  fields: ["command"],     border: "border-l-kreoz-amber", bg: "bg-kreoz-amber-dark",  pill: "bg-kreoz-amber-light text-kreoz-amber" },
  ruby:     { label: "Ruby",      icon: "◆",  fields: ["code"],        border: "border-l-kreoz-purple",bg: "bg-kreoz-purple-light",pill: "bg-kreoz-purple-light text-kreoz-purple" },
  gate:     { label: "Gate",      icon: "◇",  fields: ["condition"],   border: "border-l-kreoz-red",   bg: "bg-kreoz-red-dark",    pill: "bg-kreoz-red-light text-kreoz-red" },
  workflow: { label: "Workflow",   icon: "🔗", fields: ["workflow_id"], border: "border-l-kreoz-purple",bg: "bg-kreoz-purple-light",pill: "bg-kreoz-purple-light text-kreoz-purple" },
}
const MAX_HISTORY = 30
const PORT_CLASSES = "w-3 h-3 rounded-full border-2 cursor-crosshair absolute z-30 transition-transform hover:scale-150"

export default class extends Controller {
  static targets = ["steps", "canvas", "nombre", "defaultAgent", "runBtn", "stopBtn", "arrows"]
  static values  = { updateUrl: String, createUrl: String, persisted: Boolean, steps: Array, agents: Array, workflows: Array, nodeStates: Object, executeUrl: String }

  connect() {
    this.expandedIndex = null
    this.history = [structuredClone(this.stepsValue)]
    this.historyIdx = 0
    this.dragIdx = null
    this.linking = null // { fromName, field, fromEl }
    this._keyHandler = this.handleKey.bind(this)
    this._mouseMoveHandler = this.onLinkMouseMove.bind(this)
    this._mouseUpHandler = this.onLinkMouseUp.bind(this)
    document.addEventListener("keydown", this._keyHandler)
    this.render()
  }

  disconnect() {
    document.removeEventListener("keydown", this._keyHandler)
    document.removeEventListener("mousemove", this._mouseMoveHandler)
    document.removeEventListener("mouseup", this._mouseUpHandler)
    if (this._pollTimer) clearInterval(this._pollTimer)
  }

  // ══════════════════════════════════════════════════════════
  // GRAPH HELPERS & LOOP DETECTION
  // ══════════════════════════════════════════════════════════

  stepMap() { const m = {}; this.stepsValue.forEach(s => { if (s.name) m[s.name] = s }); return m }
  stepNames() { return this.stepsValue.map(s => s.name).filter(Boolean) }
  outEdges(step) {
    if (step.type === "gate") return [step.on_true, step.on_false].filter(Boolean)
    return step.next ? [step.next] : []
  }
  adjacency() { const a = {}; this.stepsValue.forEach(s => { a[s.name] = this.outEdges(s) }); return a }

  wouldCreateInvalidLoop(fromName, toName) {
    const adj = this.adjacency()
    adj[fromName] = [...(adj[fromName] || []), toName]
    const cycle = this.findCycle(adj, toName, fromName)
    if (!cycle) return false
    const cycleSet = new Set(cycle), map = this.stepMap()
    for (const name of cycle) {
      const s = map[name]
      if (s?.type === "gate") {
        const exits = [s.on_true, s.on_false].filter(Boolean)
        if (name === fromName) exits.push(toName)
        if (exits.some(e => !cycleSet.has(e))) return false
      }
    }
    return true
  }

  findCycle(adj, start, mustInclude) {
    const visited = new Set(), path = []
    const dfs = (node) => {
      if (node === start && path.length > 0 && path.includes(mustInclude)) return [...path]
      if (visited.has(node)) return null
      visited.add(node); path.push(node)
      for (const next of (adj[node] || [])) { const r = dfs(next); if (r) return r }
      path.pop(); visited.delete(node); return null
    }
    for (const next of (adj[start] || [])) { const r = dfs(next); if (r) return [start, ...r] }
    return null
  }

  // ══════════════════════════════════════════════════════════
  // VISUAL LINKING — drag from port to port
  // ══════════════════════════════════════════════════════════

  startLinking(fromName, field, portEl) {
    this.linking = { fromName, field, portEl }
    // Highlight all input ports as drop targets
    this.stepsTarget.querySelectorAll("[data-input-port]").forEach(p => {
      if (p.dataset.inputPort !== fromName) p.classList.add("ring-2", "ring-kreoz-green", "scale-150")
    })
    // Create temp SVG line
    const svg = this.arrowsTarget
    const line = document.createElementNS("http://www.w3.org/2000/svg", "line")
    line.id = "temp-link-line"
    line.setAttribute("stroke", field === "on_false" ? "#E24B4A" : field === "on_true" ? "#059669" : "#B4B2A9")
    line.setAttribute("stroke-width", "2")
    line.setAttribute("stroke-dasharray", "6,4")
    const rect = this.canvasTarget.getBoundingClientRect()
    const pr = portEl.getBoundingClientRect()
    line.setAttribute("x1", pr.left + pr.width / 2 - rect.left)
    line.setAttribute("y1", pr.top + pr.height / 2 - rect.top)
    line.setAttribute("x2", pr.left + pr.width / 2 - rect.left)
    line.setAttribute("y2", pr.top + pr.height / 2 - rect.top)
    svg.appendChild(line)

    document.addEventListener("mousemove", this._mouseMoveHandler)
    document.addEventListener("mouseup", this._mouseUpHandler)
  }

  onLinkMouseMove(e) {
    const line = this.arrowsTarget.querySelector("#temp-link-line")
    if (!line) return
    const rect = this.canvasTarget.getBoundingClientRect()
    line.setAttribute("x2", e.clientX - rect.left)
    line.setAttribute("y2", e.clientY - rect.top)
  }

  onLinkMouseUp(e) {
    document.removeEventListener("mousemove", this._mouseMoveHandler)
    document.removeEventListener("mouseup", this._mouseUpHandler)
    // Remove temp line and highlights
    this.arrowsTarget.querySelector("#temp-link-line")?.remove()
    this.stepsTarget.querySelectorAll("[data-input-port]").forEach(p => p.classList.remove("ring-2", "ring-kreoz-green", "scale-150"))

    if (!this.linking) return
    // Check if dropped on an input port
    const target = document.elementFromPoint(e.clientX, e.clientY)?.closest("[data-input-port]")
    if (target && target.dataset.inputPort !== this.linking.fromName) {
      this.createLink(this.linking.fromName, this.linking.field, target.dataset.inputPort)
    }
    this.linking = null
  }

  createLink(fromName, field, toName) {
    if (this.wouldCreateInvalidLoop(fromName, toName)) {
      this.toast("⛔ Blocked: this link would create an infinite loop with no exit gate.")
      return
    }
    this.pushHistory()
    const steps = [...this.stepsValue]
    const idx = steps.findIndex(s => s.name === fromName)
    if (idx < 0) return
    steps[idx] = { ...steps[idx], [field]: toName }
    this.stepsValue = steps
    this.render()
    this.autoSave()
  }

  // ══════════════════════════════════════════════════════════
  // SVG ARROW DRAWING
  // ══════════════════════════════════════════════════════════

  drawArrows() {
    const svg = this.arrowsTarget
    // Clear existing arrows (keep defs)
    svg.querySelectorAll("path.edge-arrow, text.edge-label").forEach(el => el.remove())

    const canvasRect = this.canvasTarget.getBoundingClientRect()
    const portPos = (selector) => {
      const el = this.stepsTarget.querySelector(selector)
      if (!el) return null
      const r = el.getBoundingClientRect()
      return { x: r.left + r.width / 2 - canvasRect.left, y: r.top + r.height / 2 - canvasRect.top }
    }

    this.stepsValue.forEach(step => {
      if (step.type === "gate") {
        this.drawEdge(svg, step.name, "on_true", step.on_true, portPos, "#059669", "arrow-green", "✓")
        this.drawEdge(svg, step.name, "on_false", step.on_false, portPos, "#E24B4A", "arrow-red", "✗")
      } else if (step.next) {
        this.drawEdge(svg, step.name, "next", step.next, portPos, "#B4B2A9", "arrow-gray", "")
      }
    })

    // Resize SVG to fit
    const stepsRect = this.stepsTarget.getBoundingClientRect()
    svg.style.width = stepsRect.width + "px"
    svg.style.height = stepsRect.height + "px"
  }

  drawEdge(svg, fromName, field, toName, portPos, color, marker, label) {
    if (!toName) return
    const from = portPos(`[data-output-port="${fromName}"][data-port-field="${field}"]`) || portPos(`[data-output-port="${fromName}"]`)
    const to = portPos(`[data-input-port="${toName}"]`)
    if (!from || !to) return

    const dx = to.x - from.x, dy = to.y - from.y
    // Horizontal layout: determine if backward (target is to the left)
    const isBackward = dx < 0
    const offset = isBackward ? 80 : Math.min(Math.abs(dy) * 0.5, 60)

    let d
    if (isBackward) {
      // Curve below for backward links
      const cy = Math.max(from.y, to.y) + offset
      d = `M${from.x},${from.y} C${from.x},${cy} ${to.x},${cy} ${to.x},${to.y}`
    } else if (Math.abs(dy) < 10) {
      // Nearly horizontal — straight line
      d = `M${from.x},${from.y} L${to.x},${to.y}`
    } else {
      // Forward curve (horizontal S-curve)
      const cx1 = from.x + dx * 0.4, cx2 = from.x + dx * 0.6
      d = `M${from.x},${from.y} C${cx1},${from.y} ${cx2},${to.y} ${to.x},${to.y}`
    }

    const path = document.createElementNS("http://www.w3.org/2000/svg", "path")
    path.classList.add("edge-arrow")
    path.setAttribute("d", d)
    path.setAttribute("fill", "none")
    path.setAttribute("stroke", color)
    path.setAttribute("stroke-width", "2")
    path.setAttribute("marker-end", `url(#${marker})`)
    path.style.pointerEvents = "stroke"
    path.style.cursor = "pointer"
    path.setAttribute("data-from", fromName)
    path.setAttribute("data-field", field)
    // Click to remove link
    path.addEventListener("click", () => {
      this.pushHistory()
      const steps = [...this.stepsValue]
      const idx = steps.findIndex(s => s.name === fromName)
      if (idx >= 0) { steps[idx] = { ...steps[idx], [field]: null }; this.stepsValue = steps; this.render(); this.autoSave() }
    })
    // Hover effect
    path.addEventListener("mouseenter", () => { path.setAttribute("stroke-width", "4"); path.setAttribute("stroke-opacity", "0.8") })
    path.addEventListener("mouseleave", () => { path.setAttribute("stroke-width", "2"); path.setAttribute("stroke-opacity", "1") })
    svg.appendChild(path)

    // Label for gate branches
    if (label) {
      const mx = (from.x + to.x) / 2 + (isBackward ? offset / 2 : 0)
      const my = (from.y + to.y) / 2
      const text = document.createElementNS("http://www.w3.org/2000/svg", "text")
      text.classList.add("edge-label")
      text.setAttribute("x", mx + 6)
      text.setAttribute("y", my - 4)
      text.setAttribute("fill", color)
      text.setAttribute("font-size", "11")
      text.setAttribute("font-weight", "600")
      text.textContent = label
      svg.appendChild(text)
    }
  }

  // ══════════════════════════════════════════════════════════
  // RENDERING — Tree-based layout with gate branching
  // ══════════════════════════════════════════════════════════

  render() {
    const c = this.stepsTarget
    c.innerHTML = ""

    // Build the tree layout by walking the graph from the first step
    const map = this.stepMap()
    const visited = new Set()
    const firstStep = this.stepsValue[0]
    if (!firstStep) return

    const tree = this.buildFlowTree(firstStep.name, map, visited)
    c.appendChild(tree)

    // Show orphan nodes (not reachable from the first step)
    const orphans = this.stepsValue.filter(s => !visited.has(s.name))
    if (orphans.length > 0) {
      const orphanSection = document.createElement("div")
      orphanSection.className = "mt-4 pt-4 border-t border-dashed border-gris-claro"
      const label = document.createElement("span")
      label.className = "text-xs text-gris italic mr-3"
      label.textContent = "Unlinked:"
      orphanSection.appendChild(label)
      const row = document.createElement("div")
      row.className = "flex flex-row items-center gap-2 mt-2"
      orphans.forEach(step => {
        const i = this.stepsValue.findIndex(s => s.name === step.name)
        row.appendChild(i === this.expandedIndex ? this.expandedCard(step, i) : this.flowCard(step, i))
      })
      orphanSection.appendChild(row)
      c.appendChild(orphanSection)
    }

    this.renderOutputPanel()
  }

  renderOutputPanel() {
    let panel = document.getElementById("live-output-panel")
    const hasOutput = this.stepsValue.some(s => this.nodeState(s.name)?.output)
    if (!hasOutput) { panel?.remove(); return }

    if (!panel) {
      panel = document.createElement("div")
      panel.id = "live-output-panel"
      panel.className = "mt-6 pt-4 border-t border-borde"
      this.element.querySelector("[data-workflow-editor-target='canvas']").after(panel)
    }

    panel.innerHTML = this.stepsValue.map(step => {
      const ns = this.nodeState(step.name)
      if (!ns || !ns.output) return ""
      const t = NODE_TYPES[step.type] || NODE_TYPES.kiro
      const statusColor = ns.status === "completed" ? "border-l-kreoz-green" : ns.status === "failed" ? "border-l-kreoz-red" : "border-l-kreoz-amber"
      return `<details class="mb-3 card overflow-hidden" ${ns.status === "running" ? "open" : ""}>
        <summary class="flex items-center gap-2 px-4 py-2 cursor-pointer border-l-4 ${statusColor}">
          <span>${t.icon}</span>
          <span class="font-semibold text-sm text-grafito flex-1">${step.name}</span>
          ${this.statusDot(step.name)}
          <span class="text-xs text-gris">${ns.status}</span>
        </summary>
        <pre class="px-4 py-3 bg-fondo text-xs text-grafito font-mono overflow-x-auto whitespace-pre-wrap max-h-64 overflow-y-auto">${this.esc(ns.output)}</pre>
      </details>`
    }).join("")

    // Auto-scroll running nodes to bottom
    panel.querySelectorAll("details[open] pre").forEach(pre => pre.scrollTop = pre.scrollHeight)
  }

  /** Recursively build the flow tree DOM */
  buildFlowTree(startName, map, visited, depth = 0) {
    const row = document.createElement("div")
    row.className = "flex flex-row items-center gap-2"

    let current = startName
    while (current && !visited.has(current) && depth <= 5) {
      visited.add(current)
      const step = map[current]
      if (!step) break

      const i = this.stepsValue.findIndex(s => s.name === current)

      // Add connector line before card (except first)
      if (row.children.length > 0) {
        row.appendChild(this.connectorLine())
      }

      if (step.type === "gate") {
        // Gate: render the gate card, then fork into two paths
        row.appendChild(i === this.expandedIndex ? this.expandedCard(step, i) : this.flowCard(step, i))
        row.appendChild(this.connectorLine())
        row.appendChild(this.buildGateBranch(step, map, visited, depth + 1))
        break // Gate handles its own continuation
      } else {
        row.appendChild(i === this.expandedIndex ? this.expandedCard(step, i) : this.flowCard(step, i))
        current = step.next || null
      }
    }

    return row
  }

  /** Build the visual fork for a gate node */
  buildGateBranch(gateStep, map, visited, depth) {
    const branch = document.createElement("div")
    branch.className = "flex flex-col gap-2"

    // True path
    const truePath = document.createElement("div")
    truePath.className = "flex flex-row items-center gap-2 pl-2 border-l-2 border-kreoz-green"
    const trueLabel = document.createElement("span")
    trueLabel.className = "text-xs font-bold text-kreoz-green shrink-0"
    trueLabel.textContent = "✓"
    truePath.appendChild(trueLabel)
    if (gateStep.on_true && !visited.has(gateStep.on_true)) {
      truePath.appendChild(this.buildFlowTree(gateStep.on_true, map, visited, depth))
    } else {
      truePath.appendChild(this.endMarker())
    }
    branch.appendChild(truePath)

    // False path
    const falsePath = document.createElement("div")
    falsePath.className = "flex flex-row items-center gap-2 pl-2 border-l-2 border-red-400"
    const falseLabel = document.createElement("span")
    falseLabel.className = "text-xs font-bold text-red-500 shrink-0"
    falseLabel.textContent = "✗"
    falsePath.appendChild(falseLabel)
    if (gateStep.on_false && !visited.has(gateStep.on_false)) {
      falsePath.appendChild(this.buildFlowTree(gateStep.on_false, map, visited, depth))
    } else {
      falsePath.appendChild(this.endMarker())
    }
    branch.appendChild(falsePath)

    return branch
  }

  /** Small horizontal connector line between cards */
  connectorLine() {
    const line = document.createElement("div")
    line.className = "w-6 h-0.5 bg-gris-claro shrink-0"
    return line
  }

  /** End marker for paths that don't continue */
  endMarker() {
    const el = document.createElement("span")
    el.className = "text-xs text-gris-claro italic"
    el.textContent = "end"
    return el
  }

  /** Compact card for the tree layout */
  flowCard(step, i) {
    const t = NODE_TYPES[step.type] || NODE_TYPES.kiro
    const dis = step.disabled ? "opacity-50" : ""
    const agentGlow = step.agent_id ? "shadow-[0_0_8px_var(--color-kreoz-green)] border-kreoz-green" : ""

    const el = document.createElement("div")
    el.className = `relative flex flex-col items-center gap-1 px-3 py-3 bg-fondo-card border border-borde rounded-lg shadow-sm cursor-pointer hover:border-kreoz-green hover:shadow-md transition-all duration-150 border-t-4 ${t.border.replace('border-l-', 'border-t-')} ${dis} ${agentGlow} w-36 shrink-0`
    el.dataset.index = i
    el.dataset.stepName = step.name

    el.innerHTML = `
      <span class="text-xl">${t.icon}</span>
      ${this.statusDot(step.name)}
      <span class="font-semibold text-xs text-grafito text-center truncate w-full ${step.disabled ? 'line-through' : ''}">${step.name || `${t.label} #${i + 1}`}</span>
      <span class="px-1.5 py-0.5 rounded text-xs font-medium ${t.pill}">${t.label}</span>
      <button class="actions-btn absolute top-1 right-1 w-7 h-7 flex items-center justify-center rounded-md text-gris hover:text-grafito hover:bg-gray-100 text-base font-bold" data-idx="${i}" aria-label="Actions for ${step.name || 'step'}">⋮</button>
    `

    el.addEventListener("click", (e) => { if (e.target.closest(".actions-btn")) return; this.expandedIndex = i; this.render() })
    el.querySelector(".actions-btn").addEventListener("click", (e) => { e.stopPropagation(); this.showActions(e.currentTarget, i) })

    return el
  }

  gateWarning(step, i) {
    const nextStep = this.stepsValue[i + 1]
    if (nextStep?.type === "gate" && step.type !== "gate" && (step.next === nextStep.name || (!step.next && i < this.stepsValue.length - 1)))
      return `<span class="px-1.5 py-0.5 rounded text-xs bg-amber-50 text-amber-700" title="Next step is a gate — output should be boolean">⚠ → gate</span>`
    return ""
  }

  expandedCard(step, i) {
    const t = NODE_TYPES[step.type] || NODE_TYPES.kiro
    const refs = this.availableRefs(i)

    const el = document.createElement("div")
    el.className = `relative bg-fondo-card border border-kreoz-green rounded-lg shadow-md border-t-4 ${t.border.replace('border-l-', 'border-t-')} w-72 shrink-0`
    el.dataset.stepName = step.name

    const gateWarnBanner = this.gateWarning(step, i)
      ? `<div class="mx-4 mt-3 px-3 py-2 rounded-lg bg-amber-50 border border-amber-200 text-xs text-amber-800">⚠ The next step is a <strong>Gate</strong> — this step's output will be evaluated as a boolean.</div>` : ""

    el.innerHTML = `
      <div class="${t.bg} text-white px-4 py-2 flex items-center justify-between rounded-tr-lg">
        <span class="font-semibold text-sm">${t.icon} ${t.label}</span>
        <div class="flex items-center gap-2">
          <span class="text-xs opacity-75">#${i + 1}</span>
          <button class="collapse-btn text-white/70 hover:text-white"><svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 15l-6-6-6 6"/></svg></button>
        </div>
      </div>
      ${gateWarnBanner}
      <div class="p-4 space-y-3">
        <div>
          <label class="block text-xs font-medium text-gris uppercase tracking-wide mb-1">Name</label>
          <input type="text" value="${this.esc(step.name || '')}" data-field="name" data-index="${i}" class="w-full border border-borde rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-kreoz-green" />
        </div>
        ${this.configFields(step, i)}
        ${this.linkFields(step, i)}
        ${refs.length ? `<div class="pt-2 border-t border-borde"><span class="text-xs text-gris">Available refs: </span>${refs.map(r => `<button class="ref-btn text-xs text-kreoz-green hover:underline mr-1" data-ref="${r}">{{${r}}}</button>`).join("")}</div>` : ""}
      </div>`

    el.querySelector(".collapse-btn").addEventListener("click", () => { this.expandedIndex = null; this.render() })
    el.querySelectorAll("input, textarea, select").forEach(input => {
      input.addEventListener("input", (e) => this.updateField(e))
      input.addEventListener("change", (e) => this.updateField(e))
    })
    el.querySelectorAll("select[data-link-field]").forEach(sel => {
      sel.addEventListener("change", (e) => this.handleLinkChange(e, i))
    })
    el.querySelectorAll(".ref-btn").forEach(btn => {
      btn.addEventListener("click", () => this.insertRef(btn.dataset.ref, i))
    })

    return el
  }

  linkFields(step, i) {
    const names = this.stepNames()
    const opts = (cur) => names.filter(n => n !== step.name).map(n => `<option value="${n}" ${n === cur ? "selected" : ""}>${n}</option>`).join("")
    if (step.type === "gate") {
      return `<div class="pt-3 border-t border-borde space-y-2">
        <p class="text-xs font-medium text-gris uppercase tracking-wide">Branching <span class="font-normal normal-case">(or drag from ports below)</span></p>
        <div class="grid grid-cols-2 gap-2">
          <div><label class="block text-xs text-kreoz-green font-medium mb-1">✓ True path</label>
            <select data-link-field="on_true" class="w-full border border-borde rounded-lg px-2 py-1.5 text-sm focus:outline-none focus:border-kreoz-green"><option value="">— End —</option>${opts(step.on_true)}</select></div>
          <div><label class="block text-xs text-red-500 font-medium mb-1">✗ False path</label>
            <select data-link-field="on_false" class="w-full border border-borde rounded-lg px-2 py-1.5 text-sm focus:outline-none focus:border-red-400"><option value="">— End —</option>${opts(step.on_false)}</select></div>
        </div></div>`
    }
    return `<div class="pt-3 border-t border-borde">
      <label class="block text-xs font-medium text-gris uppercase tracking-wide mb-1">Link to <span class="font-normal normal-case">(or drag from port below)</span></label>
      <select data-link-field="next" class="w-full border border-borde rounded-lg px-3 py-1.5 text-sm focus:outline-none focus:border-kreoz-green"><option value="">— Next in list —</option>${opts(step.next)}</select></div>`
  }

  handleLinkChange(e, stepIdx) {
    const field = e.target.dataset.linkField, target = e.target.value, step = this.stepsValue[stepIdx]
    if (target && this.wouldCreateInvalidLoop(step.name, target)) {
      e.target.value = step[field] || ""
      this.toast("⛔ Blocked: this link would create an infinite loop with no exit gate.")
      return
    }
    this.pushHistory()
    const steps = [...this.stepsValue]
    steps[stepIdx] = { ...steps[stepIdx], [field]: target || null }
    this.stepsValue = steps; this.render(); this.autoSave()
  }

  configFields(step, i) {
    const t = NODE_TYPES[step.type] || NODE_TYPES.kiro
    let html = ""
    if (step.type === "kiro" && this.agentsValue.length > 0) {
      html += `<div><label class="block text-xs font-medium text-gris uppercase tracking-wide mb-1">Agent</label>
        <select data-field="agent_id" data-index="${i}" class="w-full border border-borde rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-kreoz-green">
          <option value="">— Inherit from workflow —</option>
          ${this.agentsValue.map(a => `<option value="${a.id}" ${a.id === step.agent_id ? "selected" : ""}>${a.nombre}</option>`).join("")}
        </select></div>`
    }
    if (step.type === "kiro") {
      html += `<div><label class="block text-xs font-medium text-gris uppercase tracking-wide mb-1">Model</label>
        <select data-field="model" data-index="${i}" class="w-full border border-borde rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-kreoz-green">
          <option value="" ${!step.model ? "selected" : ""}>— Default —</option>
          ${["auto","claude-opus-4.6","claude-sonnet-4.6","claude-opus-4.5","claude-sonnet-4.5","claude-sonnet-4","claude-haiku-4.5","minimax-m2.5","minimax-m2.1","glm-5","qwen3-coder-next"].map(m => `<option value="${m}" ${m === step.model ? "selected" : ""}>${m}</option>`).join("")}
        </select></div>`
    }
    if (step.type === "workflow") {
      html += `<div><label class="block text-xs font-medium text-gris uppercase tracking-wide mb-1">Sub-workflow</label>
        <select data-field="workflow_id" data-index="${i}" class="w-full border border-borde rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-blue-500">
          <option value="">— Select a workflow —</option>
          ${this.workflowsValue.map(w => `<option value="${w.id}" ${w.id === step.workflow_id ? "selected" : ""}>${w.nombre}</option>`).join("")}
        </select></div>`
      return html
    }
    html += t.fields.map(field => {
      const val = this.esc(step[field] || ""), isLong = field === "prompt" || field === "code"
      return `<div><label class="block text-xs font-medium text-gris uppercase tracking-wide mb-1">${field}</label>
        ${isLong
          ? `<textarea data-field="${field}" data-index="${i}" rows="3" class="w-full border border-borde rounded-lg px-3 py-2 text-sm font-mono focus:outline-none focus:border-kreoz-green" placeholder="{{prev}} references the previous step...">${val}</textarea>`
          : `<input type="text" value="${val}" data-field="${field}" data-index="${i}" class="w-full border border-borde rounded-lg px-3 py-2 text-sm font-mono focus:outline-none focus:border-kreoz-green" placeholder="${field === "condition" ? 'ctx[:prev].include?("success")' : "echo {{prev}}"}" />`
        }</div>`
    }).join("")
    return html
  }

  // ══════════════════════════════════════════════════════════
  // ACTIONS / UNDO / KEYBOARD / MUTATIONS
  // ══════════════════════════════════════════════════════════

  dropAt(targetIdx) {
    if (this.dragIdx === null || this.dragIdx === targetIdx) return
    this.pushHistory()
    const steps = [...this.stepsValue]
    const [moved] = steps.splice(this.dragIdx, 1)
    steps.splice(targetIdx > this.dragIdx ? targetIdx - 1 : targetIdx, 0, moved)
    this.stepsValue = steps; this.expandedIndex = null; this.render(); this.autoSave()
  }

  showActions(btn, i) {
    this.closeMenu()
    const menu = document.createElement("div")
    menu.className = "actions-menu fixed bg-fondo-card border border-borde rounded-lg shadow-lg py-1 z-[9999] min-w-[160px] text-sm"
    const rect = btn.getBoundingClientRect()
    menu.style.top = `${rect.bottom + 4}px`
    menu.style.left = `${rect.right - 160}px`
    const step = this.stepsValue[i]
    menu.innerHTML = `
      <button class="w-full text-left px-3 py-1.5 hover:bg-gray-50" data-act="insert-before">+ Insert before</button>
      <button class="w-full text-left px-3 py-1.5 hover:bg-gray-50" data-act="duplicate">Duplicate</button>
      <button class="w-full text-left px-3 py-1.5 hover:bg-gray-50" data-act="toggle">${step.disabled ? "Enable" : "Disable"}</button>
      <button class="w-full text-left px-3 py-1.5 hover:bg-gray-50" data-act="move-up" ${i === 0 ? "disabled" : ""}>↑ Move up</button>
      <button class="w-full text-left px-3 py-1.5 hover:bg-gray-50" data-act="move-down" ${i === this.stepsValue.length - 1 ? "disabled" : ""}>↓ Move down</button>
      <hr class="my-1 border-borde"/>
      <button class="w-full text-left px-3 py-1.5 hover:bg-red-50 text-red-600" data-act="delete">Delete</button>`
    menu.addEventListener("click", (e) => {
      const act = e.target.dataset.act; if (!act) return; this.closeMenu()
      if (act === "insert-before") this.insertBefore(i)
      else if (act === "duplicate") this.duplicate(i)
      else if (act === "toggle") this.toggleDisabled(i)
      else if (act === "move-up") this.move(i, -1)
      else if (act === "move-down") this.move(i, 1)
      else if (act === "delete") this.removeStep(i)
    })
    document.body.appendChild(menu)
    setTimeout(() => document.addEventListener("click", this._closeMenuHandler = () => this.closeMenu(), { once: true }))
  }
  closeMenu() { document.querySelectorAll(".actions-menu").forEach(m => m.remove()) }

  pushHistory() {
    this.history = this.history.slice(0, this.historyIdx + 1)
    this.history.push(structuredClone(this.stepsValue))
    if (this.history.length > MAX_HISTORY) this.history.shift()
    this.historyIdx = this.history.length - 1
  }
  undo() { if (this.historyIdx <= 0) return; this.historyIdx--; this.stepsValue = structuredClone(this.history[this.historyIdx]); this.expandedIndex = null; this.render(); this.autoSave(); this.toast("Undone", "Redo", () => this.redo()) }
  redo() { if (this.historyIdx >= this.history.length - 1) return; this.historyIdx++; this.stepsValue = structuredClone(this.history[this.historyIdx]); this.expandedIndex = null; this.render(); this.autoSave() }

  handleKey(e) {
    if (e.target.matches("input, textarea, select")) { if (e.key === "Escape") { this.expandedIndex = null; this.render(); e.preventDefault() }; return }
    const ctrl = e.ctrlKey || e.metaKey
    if (ctrl && e.key === "z" && !e.shiftKey) { this.undo(); e.preventDefault() }
    else if (ctrl && (e.key === "Z" || (e.key === "z" && e.shiftKey))) { this.redo(); e.preventDefault() }
    else if (ctrl && e.key === "d") { this.duplicate(this.expandedIndex ?? this.stepsValue.length - 1); e.preventDefault() }
    else if (ctrl && e.key === "ArrowUp") { this.move(this.expandedIndex, -1); e.preventDefault() }
    else if (ctrl && e.key === "ArrowDown") { this.move(this.expandedIndex, 1); e.preventDefault() }
    else if (e.key === "Escape") { this.expandedIndex = null; this.render() }
  }

  addStep(event) {
    const type = event.currentTarget.dataset.nodeType || "kiro"
    this.pushHistory()
    const steps = [...this.stepsValue]
    const newName = `${type}_${steps.length + 1}`
    const newStep = { type, name: newName, prompt: "", command: "", code: "", condition: "true" }
    const insertAt = this.expandedIndex != null ? this.expandedIndex + 1 : steps.length
    steps.splice(insertAt, 0, newStep); this.stepsValue = steps; this.expandedIndex = insertAt; this.render(); this.autoSave()
    this.toast(this.expandedIndex === 0 ? "Step added at the beginning." : `Step inserted at position #${insertAt + 1}.`)
  }

  insertBefore(i) {
    this.pushHistory()
    const steps = [...this.stepsValue]
    const newName = `kiro_${steps.length + 1}`
    const newStep = { type: "kiro", name: newName, prompt: "", command: "", code: "", condition: "true" }
    steps.splice(i, 0, newStep); this.stepsValue = steps; this.expandedIndex = i; this.render(); this.autoSave()
  }

  removeStep(i) {
    this.pushHistory(); const steps = [...this.stepsValue]; const removed = steps[i]
    steps.forEach((s, j) => { if (j === i) return; if (s.next === removed.name) steps[j] = { ...s, next: null }; if (s.on_true === removed.name) steps[j] = { ...s, on_true: null }; if (s.on_false === removed.name) steps[j] = { ...s, on_false: null } })
    steps.splice(i, 1); this.stepsValue = steps; this.expandedIndex = null; this.render(); this.autoSave(); this.toast("Step deleted", "Undo", () => this.undo())
  }

  duplicate(i) {
    if (i == null || i < 0) return; this.pushHistory(); const steps = [...this.stepsValue]; const orig = steps[i]; const newName = `${orig.name}_copy`
    const dup = { ...orig, name: newName, next: null, on_true: null, on_false: null }
    if (orig.type === "gate") { if (!orig.on_true) steps[i] = { ...orig, on_true: newName } } else { steps[i] = { ...orig, next: newName } }
    steps.splice(i + 1, 0, dup); this.stepsValue = steps; this.expandedIndex = i + 1; this.render(); this.autoSave()
  }

  toggleDisabled(i) { this.pushHistory(); const steps = [...this.stepsValue]; steps[i] = { ...steps[i], disabled: !steps[i].disabled }; this.stepsValue = steps; this.render(); this.autoSave() }

  move(i, dir) {
    if (i == null) return; const j = i + dir; if (j < 0 || j >= this.stepsValue.length) return
    this.pushHistory(); const steps = [...this.stepsValue]; [steps[i], steps[j]] = [steps[j], steps[i]]; this.stepsValue = steps; this.expandedIndex = j; this.render(); this.autoSave()
  }

  updateField(e) { const { index, field } = e.target.dataset; if (!index || !field) return; const steps = [...this.stepsValue]; steps[parseInt(index)] = { ...steps[parseInt(index)], [field]: e.target.value }; this.stepsValue = steps; this.autoSave() }

  insertRef(ref, i) {
    const ta = this.stepsTarget.querySelector(`textarea[data-index="${i}"]`); if (!ta) return
    const pos = ta.selectionStart, val = ta.value
    ta.value = val.slice(0, pos) + `{{${ref}}}` + val.slice(pos); ta.focus(); ta.selectionStart = ta.selectionEnd = pos + ref.length + 4
    ta.dispatchEvent(new Event("input", { bubbles: true }))
  }

  // ══════════════════════════════════════════════════════════
  // RUN EXECUTION & POLLING
  // ══════════════════════════════════════════════════════════

  async runWorkflow() {
    if (!this.executeUrlValue) return
    const btn = this.hasRunBtnTarget ? this.runBtnTarget : null
    const stopBtn = this.hasStopBtnTarget ? this.stopBtnTarget : null
    if (btn) { btn.disabled = true; btn.textContent = "⏳ Running…" }
    if (stopBtn) { stopBtn.classList.remove("hidden") }
    this.nodeStatesValue = {}
    this._runStartedAt = Date.now()
    this.showRunBanner("running")
    this.render()

    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    try {
      const resp = await fetch(this.executeUrlValue, { method: "POST", headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf }, body: JSON.stringify({}) })
      if (!resp.ok) throw new Error("Failed to start run")
      const { run_id, status_url } = await resp.json()
      this._pollUrl = status_url
      this._stopUrl = status_url.replace(/\.json$/, "/stop.json")
      this._pollTimer = setInterval(() => this.pollRunStatus(), 1000)
    } catch (e) {
      this.showRunBanner("failed", e.message)
      if (btn) { btn.disabled = false; btn.textContent = "▶ Run" }
      if (stopBtn) { stopBtn.classList.add("hidden") }
    }
  }

  async stopWorkflow() {
    if (!this._stopUrl) return
    const stopBtn = this.hasStopBtnTarget ? this.stopBtnTarget : null
    if (stopBtn) { stopBtn.disabled = true; stopBtn.textContent = "⏹ Stopping…" }
    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    try {
      await fetch(this._stopUrl, { method: "POST", headers: { "X-CSRF-Token": csrf } })
    } catch { /* poll will pick up the status change */ }
  }

  async pollRunStatus() {
    if (!this._pollUrl) return
    try {
      const resp = await fetch(this._pollUrl)
      const data = await resp.json()
      this.nodeStatesValue = data.node_states || {}
      this.showRunBanner("running") // update elapsed time
      this.render()
      if (data.status === "completed" || data.status === "failed" || data.status === "cancelled") {
        clearInterval(this._pollTimer)
        this._pollTimer = null
        this._stopUrl = null
        this.showRunBanner(data.status, data.error_message)
        const btn = this.hasRunBtnTarget ? this.runBtnTarget : null
        const stopBtn = this.hasStopBtnTarget ? this.stopBtnTarget : null
        if (btn) { btn.disabled = false; btn.textContent = "▶ Run" }
        if (stopBtn) { stopBtn.classList.add("hidden"); stopBtn.disabled = false; stopBtn.textContent = "⏹ Stop" }
      }
    } catch { /* retry on next tick */ }
  }

  elapsedStr() {
    if (!this._runStartedAt) return ""
    const s = Math.floor((Date.now() - this._runStartedAt) / 1000)
    return s < 60 ? `${s}s` : `${Math.floor(s / 60)}m ${s % 60}s`
  }

  showRunBanner(status, message) {
    let banner = document.getElementById("run-status-banner")
    if (!banner) {
      banner = document.createElement("div")
      banner.id = "run-status-banner"
      this.element.insertBefore(banner, this.element.children[1])
    }
    banner.className = "mb-4 px-4 py-2 rounded-lg text-sm font-medium flex items-center gap-2"
    if (status === "running") {
      banner.classList.add("bg-kreoz-amber-light", "text-kreoz-amber")
      banner.innerHTML = `<span class="w-2.5 h-2.5 rounded-full bg-kreoz-amber animate-pulse shadow-[0_0_6px_var(--color-kreoz-amber)]"></span> Workflow running… <span class="text-xs opacity-75">${this.elapsedStr()}</span>`
    } else if (status === "completed") {
      banner.classList.add("bg-kreoz-green-light", "text-kreoz-green")
      banner.innerHTML = '<span class="w-2.5 h-2.5 rounded-full bg-kreoz-green shadow-[0_0_6px_var(--color-kreoz-green)]"></span> Workflow completed'
      setTimeout(() => banner.remove(), 5000)
    } else if (status === "cancelled") {
      banner.classList.add("bg-gray-100", "text-gris")
      banner.innerHTML = '<span class="w-2.5 h-2.5 rounded-full bg-gray-400"></span> Workflow stopped'
      setTimeout(() => banner.remove(), 5000)
    } else {
      banner.classList.add("bg-kreoz-red-light", "text-kreoz-red")
      banner.innerHTML = `<span class="w-2.5 h-2.5 rounded-full bg-kreoz-red shadow-[0_0_6px_var(--color-kreoz-red)]"></span> Workflow failed${message ? `: ${message}` : ""}`
    }
  }

  // ══════════════════════════════════════════════════════════
  // HELPERS & PERSISTENCE
  // ══════════════════════════════════════════════════════════

  availableRefs(i) { return ["input", ...this.stepsValue.slice(0, i).map(s => s.name).filter(Boolean)] }
  subWorkflowLabel(wfId) { const wf = this.workflowsValue.find(w => w.id === wfId); return wf ? `<span class="hidden sm:inline px-1.5 py-0.5 rounded text-xs bg-blue-50 text-blue-600">→ ${wf.nombre}</span>` : "" }
  nodeState(name) {
    const s = (this.nodeStatesValue || {})[name]
    if (!s) return null
    if (typeof s === "string") return { status: s, output: "" }
    return { status: s.status, output: s.output || "" }
  }
  statusDot(name) {
    const s = this.nodeState(name)?.status
    if (s === "completed") return '<span class="w-2.5 h-2.5 rounded-full bg-kreoz-green shadow-[0_0_6px_var(--color-kreoz-green)] shrink-0"></span>'
    if (s === "failed") return '<span class="w-2.5 h-2.5 rounded-full bg-kreoz-red shadow-[0_0_6px_var(--color-kreoz-red)] shrink-0"></span>'
    if (s === "running") return '<span class="w-2.5 h-2.5 rounded-full bg-kreoz-amber animate-pulse shadow-[0_0_6px_var(--color-kreoz-amber)] shrink-0"></span>'
    return ''
  }
  esc(s) { return s.replace(/"/g, "&quot;").replace(/</g, "&lt;") }
  toast(msg, actionLabel, actionFn) {
    const t = document.createElement("div")
    t.className = "fixed bottom-6 left-1/2 -translate-x-1/2 bg-grafito text-white px-4 py-2 rounded-lg shadow-lg text-sm flex items-center gap-3 z-50 max-w-md text-center"
    t.innerHTML = `<span>${msg}</span>${actionLabel ? `<button class="text-kreoz-green font-semibold hover:underline">${actionLabel}</button>` : ""}`
    if (actionFn) t.querySelector("button")?.addEventListener("click", () => { actionFn(); t.remove() })
    document.body.appendChild(t); setTimeout(() => t.remove(), 4000)
  }

  autoSave() { if (!this.persistedValue) return; clearTimeout(this._t); this._t = setTimeout(() => this.save(), 600) }

  async save() {
    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    await fetch(this.updateUrlValue, { method: "PATCH", headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf }, body: JSON.stringify({ workflow_definition: { drawflow_data: { steps: this.stepsValue } } }) })
  }

  async manualSave() {
    if (!this.persistedValue) return
    await this.save()
    this.toast("Saved ✓")
  }

  async createWorkflow() {
    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    const resp = await fetch(this.createUrlValue, { method: "POST", headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf }, body: JSON.stringify({ workflow_definition: { nombre: this.nombreTarget.value, drawflow_data: { steps: this.stepsValue } } }) })
    if (resp.ok) { const data = await resp.json(); window.location.href = data.url || resp.headers.get("Location") || "/workflows" }
    else if (resp.redirected) { window.location.href = resp.url }
  }

  async saveNombre() {
    if (!this.persistedValue) return; const csrf = document.querySelector("meta[name='csrf-token']")?.content
    await fetch(this.updateUrlValue, { method: "PATCH", headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf }, body: JSON.stringify({ workflow_definition: { nombre: this.nombreTarget.value } }) })
  }

  async saveDefaultAgent() {
    if (!this.persistedValue) return; const csrf = document.querySelector("meta[name='csrf-token']")?.content
    const agentId = this.hasDefaultAgentTarget ? this.defaultAgentTarget.value : ""
    await fetch(this.updateUrlValue, { method: "PATCH", headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf }, body: JSON.stringify({ workflow_definition: { default_agent_id: agentId || null } }) })
  }
}
