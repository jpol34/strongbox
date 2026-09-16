# Strongbox UI - Design System

Dark-only, single-page internal tool. Small surface, but a real system: tokens + a handful of
reusable components, so a future page (or a second view on this one) drops in without guessing.

## Palette

CSS custom properties, defined on `:root`.

| Token | Value | Use |
|---|---|---|
| `--bg` | `#0d1117` | Page background |
| `--surface` | `#161b22` | Cards, header, form |
| `--surface-raised` | `#1c2129` | Table row hover, inputs |
| `--border` | `#30363d` | Hairlines, table rules |
| `--text` | `#e6edf3` | Primary text |
| `--text-muted` | `#8b949e` | Secondary text, labels |
| `--accent` | `#58a6ff` | Links, primary actions, focus ring |
| `--accent-hover` | `#79b8ff` | Primary action hover |
| `--danger` | `#f85149` | Errors |
| `--warn` | `#d29922` | Staleness badge |
| `--warn-bg` | `#3a2e0e` | Staleness row/badge background |
| `--success` | `#3fb950` | Save confirmation |

Palette is a muted GitHub-dark-adjacent scheme - legible, low-glare for a tool you'll have open
next to a terminal, and reuses hues you already associate with "code/infra tooling" rather than
inventing a new brand identity for an internal page.

## Type scale

System font stack (`-apple-system, "Segoe UI", sans-serif` - no webfont for an internal tool).

| Token | Size | Use |
|---|---|---|
| `--text-xs` | 0.75rem | Badges, meta (last rotated, counts) |
| `--text-sm` | 0.875rem | Table body, form inputs |
| `--text-base` | 1rem | Body default |
| `--text-lg` | 1.25rem | Section headings |
| `--text-xl` | 1.75rem | Page title |

Monospace (`ui-monospace, "SF Mono", Consolas, monospace`) for secret names and revealed values:
these are identifiers/tokens, not prose.

## Spacing

4px base unit, exposed as `--space-1` (4px) through `--space-8` (32px), doubling: 1/2/3/4/6/8.
All padding/margin/gap in the CSS references these - no bare `px`/`rem` literals in component
rules.

## Components

- **Card** (`.card`): `--surface` background, `--border` hairline, `--space-4` padding, 8px
  radius. The table sits in a card; the toolbar (wordmark/search/action icons) deliberately does
  not - it sits directly on the page background.
- **Button** (`.btn`, `.btn-primary`, `.btn-ghost`, `.btn-danger`): primary = accent-filled for
  the one main affirmative action per surface (Save, Reload); ghost = bordered-only for secondary
  actions (Reveal, Copy, Cancel, Close); danger = red-outlined, fills solid red on hover, used
  only for Delete - and only rendered at all when editing an existing secret (a create-mode modal
  has no Delete button to show).
- **Input** (`.input`): consistent height/padding/border/focus-ring across text, password,
  number fields.
- **Badge** (`.badge`, `.badge-warn`): pill shape, `--text-xs`, used for the staleness indicator.
- **Table** (`.table`): hairline row dividers, hover highlight via `--surface-raised`, monospace
  name column, fixed per-column widths (`table-layout: fixed`) so long `usedBy`/`purpose` text
  ellipsizes instead of reflowing the whole table.
- **Modal** (`<dialog>` + `.modal`/`.modal-body`/`.modal-actions`): native `<dialog>` via
  `showModal()` - backdrop, focus containment, and Escape-to-close all come from the platform for
  free. Two instances: `#secret-modal` (add/update/delete a secret - one form, mode-dependent
  title/fields) and `#reveal-modal` (a single revealed value + copy button). Actions split left
  (Save/Cancel, or just Close) vs. right (status text, and Delete when present) via
  `.modal-actions-left`/`-right`. Both are labeled via `aria-labelledby` pointing at their own
  `<h2>` and autofocus their first meaningful control.
- **Disclosure** (`.disclosure`): native `<details>/<summary>` styled to match the button
  language, used for the Settings popover. Closes on outside-click or Escape, matching the
  modals' Escape behavior.
- **Icon button** (`.icon-btn`): inline SVG (stroke=currentColor, no fill) instead of text, used
  for Settings (gear), Add (+), and per-row Reveal (eye) / Edit (pencil) / Copy, actions common
  enough to not need a label once learned. The action column shows two icons per row: Reveal
  opens `#reveal-modal`; Edit opens `#secret-modal` in edit mode. There is no whole-row click
  target; only the icons are interactive.

## Auth persistence

The bearer token is generated once and written to `.token` (gitignored) rather than re-minted per
launch - the page saves it to `localStorage` after first successful load, so in practice you
paste it once, ever. A 401 clears the saved copy (handles the case where `.token` was deleted to
force rotation). `Start-StrongboxUi.ps1 -RotateToken` forces a fresh one on demand.

## Interaction notes

- Revealed secret values auto-close the reveal modal after 15s; a successful copy additionally
  clears the clipboard 30s later (only if it still holds the value this app put there): this
  tool's security posture is shared between the UI and the backend.
- Focus states: buttons get an `--accent` outline (`:focus-visible`); text/number inputs get an
  `--accent`-tinted box-shadow ring instead (`.input:focus`) - visually different treatment, same
  purpose. Keyboard nav matters even on a one-person tool - you'll tab through this at 2am during
  an incident.
- Empty states are context-dependent: "no secrets loaded" (nothing fetched yet) reads differently
  from "no secrets match "x"" (loaded, but the search filtered everything out) - same `#empty`
  element, different copy depending on which case it is.
- All four mutating actions (load, save, delete, reveal) show a loading state, a distinct error
  message covering both network-level failures and non-2xx responses, and a success
  confirmation - no action silently does nothing on failure.
