# Flight Control — Workflow Editor UX Improvement Proposal

**Date**: 2026-04-18
**Status**: Proposal
**Constraint**: No external JS dependencies. Vanilla JS + Stimulus + Tailwind + Kreoz design system only.

---

## Problem Statement

The current editor works but feels unintuitive because:

1. **Cards are always fully expanded** — with 5+ steps, the page becomes a wall of forms. You lose the "flow at a glance" feeling that makes n8n/Pipedream satisfying.
2. **No reordering** — must delete and re-add steps to change order.
3. **No card lifecycle actions** — can't duplicate, disable, or move steps.
4. **No execution feedback on cards** — status lives only in the run history footer.
5. **No data flow visibility** — `{{name}}` references are invisible; you have to read the prompt text to understand dependencies.
6. **No undo** — one wrong delete and the step is gone.

---

## Core Design Principle: Compact by Default, Expand to Edit

The single biggest UX win from studying n8n, Pipedream, Zapier, and HighLevel:

> **Cards should show just enough to understand the flow at a glance. Expand only when editing.**

This transforms the editor from "a list of forms" into "a visual pipeline you can scan in 2 seconds."

---

## Proposed Card States

### 1. Collapsed State (default) — ~56px tall

```
┌─────────────────────────────────────────────────────────┐
│ ⠿  ⚡ analyze          Kiro AI    ← input    ● ✓   ⋮  │
│ grip icon  name         badge     deps     status menu │
└─────────────────────────────────────────────────────────┘
```

Components left-to-right:
- **Drag handle** (`⠿` grip dots) — grab to reorder
- **Type icon + color bar** — left border colored by type (green/amber/purple/red)
- **Step name** — bold, truncated if long
- **Type badge** — small pill: "Kiro AI", "Shell", "Ruby", "Gate"
- **Dependency pills** — small gray pills showing `← stepName` for each `{{ref}}`
- **Status indicator** — dot: ⚪ idle, 🟢 success, 🔴 failed, 🔵 running (animated pulse)
- **Actions menu** (`⋮`) — three-dot dropdown

Click anywhere on the collapsed card → expands it.

### 2. Expanded State (editing) — variable height

```
┌─────────────────────────────────────────────────────────┐
│ ⠿  ⚡ Kiro AI                              ▲  #2   ⋮  │
├─────────────────────────────────────────────────────────┤
│  Nombre: [analyze                              ]       │
│                                                         │
│  Agente: [— Heredar del workflow —          ▾]         │
│                                                         │
│  Prompt:                                                │
│  ┌─────────────────────────────────────────────────┐   │
│  │ Analyze this feature: {{input}}                 │   │
│  │                                                 │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
│  Refs disponibles: input, plan, implement               │
└─────────────────────────────────────────────────────────┘
```

Changes from current:
- **No "Tipo" dropdown** — type is set at creation, shown as header badge. Change type via actions menu if needed.
- **Collapse chevron** (`▲`) — click to collapse back.
- **Available refs hint** — shows which `{{names}}` are available from upstream steps.
- **Only one card expanded at a time** (accordion behavior) — keeps the page scannable.

### 3. Disabled State

```
┌─────────────────────────────────────────────────────────┐
│ ⠿  ⚡ analyze          Kiro AI    ← input    ⊘    ⋮  │  ← opacity-50, strikethrough name
└─────────────────────────────────────────────────────────┘
```

- Greyed out (opacity 50%)
- `⊘` icon instead of status dot
- Skipped during execution (treated like a gate that returns false)
- Toggle via actions menu: "Desactivar" / "Activar"

---

## Feature Breakdown

### A. Drag-to-Reorder (HTML5 Drag API)

No library needed. The HTML5 Drag and Drop API handles vertical list reordering natively:

- Drag handle (`.drag-handle`) gets `draggable="true"`
- On `dragstart`: add `.dragging` class (opacity 0.4, scale 0.98)
- On `dragover`: calculate insertion point using `getBoundingClientRect()`
- On `drop`: splice the steps array, re-render, auto-save
- Visual placeholder: a 4px colored line where the card will land

**Keyboard alternative**: `Ctrl+↑` / `Ctrl+↓` moves the selected card up/down.

### B. Actions Menu (three-dot `⋮`)

Dropdown with:
- **Duplicar** (Ctrl+D) — clones the step, appends `_copy` to name
- **Desactivar/Activar** — toggles disabled state
- **Cambiar tipo** → submenu with type options
- **Eliminar** (Delete/Backspace) — with undo toast, not a confirm dialog

### C. Undo/Redo Stack

Simple implementation:
- `history[]` array of steps snapshots (max 30 entries)
- `historyIndex` pointer
- Every mutation pushes a snapshot
- `Ctrl+Z` → decrement index, restore
- `Ctrl+Shift+Z` → increment index, restore
- Visual: subtle toast "Deshecho" with "Rehacer" link (auto-dismiss 3s)

### D. Execution Status on Cards

During/after a run, cards show their individual status:

| State | Visual |
|-------|--------|
| Idle | ⚪ small gray dot |
| Queued | ⚪ hollow circle |
| Running | 🔵 pulsing blue dot (CSS animation) |
| Success | 🟢 solid green dot |
| Failed | 🔴 solid red dot + subtle red left border |
| Skipped | ⚪ dash icon |
| Disabled | ⊘ muted icon |

Update via ActionCable — the `WorkflowRunChannel` already broadcasts status. Just need to map `node_states` to card UI.

### E. Dependency Visualization

Parse each step's config fields for `{{name}}` patterns. Show as small pills:

```html
<span class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-xs bg-gray-100 text-gris">
  ← input
</span>
```

This makes the data flow visible without reading the prompt text. At a glance you can see: "analyze depends on input, plan depends on analyze."

### F. Available References Hint (in expanded state)

When editing a step, show which upstream step names are available for `{{}}` interpolation:

```
Refs disponibles: input, analyze, plan
```

Computed from all steps above the current one in the array. Clicking a ref name inserts `{{name}}` at cursor position in the active textarea.

### G. Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+Z` | Undo |
| `Ctrl+Shift+Z` | Redo |
| `Ctrl+D` | Duplicate selected card |
| `Delete` / `Backspace` | Delete selected card (when not in input) |
| `Ctrl+↑` | Move card up |
| `Ctrl+↓` | Move card down |
| `Escape` | Collapse current card |
| `Enter` (on collapsed card) | Expand card |

### H. Connector Arrows Upgrade

Replace the static SVG arrow with a styled connector that reinforces the flow:

```
     │
     ▼  (animated dot traveling down during execution)
     │
```

During execution, a small dot animates along the connector from the completed step to the next running step. Pure CSS animation on a pseudo-element.

---

## Visual Design (Kreoz System)

### Color Mapping (unchanged, just applied differently)

| Type | Left border | Header bg (expanded) | Badge bg |
|------|-------------|---------------------|----------|
| Kiro | `kreoz-green` | `kreoz-green` | `bg-kreoz-green/10 text-kreoz-green` |
| Shell | `kreoz-amber` | `kreoz-amber` | `bg-kreoz-amber/10 text-kreoz-amber-dark` |
| Ruby | `kreoz-purple` | `kreoz-purple` | `bg-kreoz-purple/10 text-kreoz-purple` |
| Gate | `kreoz-red` | `kreoz-red` | `bg-kreoz-red/10 text-kreoz-red` |

### Collapsed Card CSS

```css
.step-card-collapsed {
  @apply flex items-center gap-3 px-4 py-3 
         bg-white border border-borde rounded-lg
         shadow-sm cursor-pointer
         hover:border-kreoz-green hover:shadow-md
         transition-all duration-150;
  border-left: 4px solid var(--step-color);
}

.step-card-collapsed.disabled {
  @apply opacity-50;
}

.step-card-collapsed.dragging {
  @apply opacity-40 scale-[0.98] shadow-lg;
}
```

### Expanded Card CSS

```css
.step-card-expanded {
  @apply bg-white border border-kreoz-green rounded-lg shadow-md;
  border-left: 4px solid var(--step-color);
}
```

### Status Dot Animation

```css
.status-running {
  @apply w-2.5 h-2.5 rounded-full bg-blue-500;
  animation: pulse-status 1.5s ease-in-out infinite;
}

@keyframes pulse-status {
  0%, 100% { opacity: 1; transform: scale(1); }
  50% { opacity: 0.5; transform: scale(1.3); }
}
```

---

## Implementation Priority

### Phase 1 — Immediate Impact (1-2 days)

1. **Collapsed/Expanded card states** — biggest UX win, transforms the feel
2. **Remove redundant "Tipo" dropdown** — less noise per card
3. **Available refs hint** — reduces cognitive load when writing prompts

### Phase 2 — Interaction Quality (1-2 days)

4. **Drag-to-reorder** — HTML5 Drag API, ~50 lines
5. **Actions menu** (duplicate, disable, delete) — standard dropdown
6. **Undo/Redo** — history stack, ~40 lines

### Phase 3 — Polish (1 day)

7. **Execution status on cards** — wire ActionCable node_states to card dots
8. **Dependency pills** — regex parse `{{name}}` from config fields
9. **Keyboard shortcuts** — event listener on the container
10. **Connector animation** — CSS-only during execution

---

## What NOT to Do

- **Don't add a free-form canvas** — the linear card flow is the right abstraction for sequential pipelines. A canvas adds complexity without value for this use case.
- **Don't add zoom/pan** — not needed for a vertical list of 3-15 cards.
- **Don't add a sidebar panel** — editing inline (expanded card) is faster than a separate panel for this card count.
- **Don't add drag-from-palette** — the toolbar buttons are fine for adding steps. Drag-from-palette is overkill for 4 node types.

---

## Data Model Impact

Add one field to the step JSON:

```json
{
  "type": "kiro",
  "name": "analyze",
  "prompt": "...",
  "disabled": false  // ← new
}
```

The `DrawflowConverter` should skip steps where `disabled: true`.

No other schema changes needed. The collapsed/expanded state is purely UI (not persisted).

---

## Comparison: Before vs After

### Before (current)
- See 3 cards on screen → scroll to see the rest
- Every card shows all fields always → visual noise
- Can't tell the flow shape without reading each prompt
- Accidentally delete a step → gone forever

### After (proposed)
- See 8-10 cards on screen in collapsed view → entire flow visible
- Click to edit one card at a time → focused editing
- Dependency pills show the flow shape at a glance
- Undo brings it back instantly
- Drag to reorder in 1 second vs delete-and-recreate

---

## Reference Implementations Studied

- **n8n**: Canvas-based, nodes with compact view + side panel for editing. We take the "compact by default" principle but keep inline editing (simpler for linear flows).
- **Pipedream**: Linear card flow similar to ours, but with collapsed states and status indicators. Closest reference.
- **Zapier**: Collapsed cards with expand-on-click. Very clean. Our main inspiration for the collapsed state.
- **HighLevel**: Undo/redo with keyboard shortcuts and recent changes list.
- **Userflow**: Keyboard navigation, copy/paste blocks, full undo/redo in a flow builder.
