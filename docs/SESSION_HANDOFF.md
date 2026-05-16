# Session handoff — Trade tab restructuring

_Last updated: 2026-05-16_

This document captures live context for a Claude Code session resuming the
Trade tab UI workstream. Read this **before** making changes.

---

## Recently shipped

### PR #23 — `Live | Paper` sub-tab strip on Trade tab
- Live sub-tab body = original Trade page content **verbatim** (incl. the auto-execution mode card)
- Paper sub-tab body = `PaperTradesPage`
- Added footer link on Pulse page

Because Live's body was preserved verbatim, the Trade tab now shows the **word "Paper" twice** with different meanings:
- Sub-tab strip "Paper" = view filter ("show me paper trades")
- Auto-execution mode card "Paper" = engine global setting ("execute as paper")

---

## In flight

### `fix/auto-mode-above-subtabs` (PR TBD)
Hoists the auto-execution mode card **above** the sub-tab strip so it's always visible and no longer collides semantically with the Paper sub-tab.

Target structure after merge:

```
Trade tab Scaffold
├── AppBar (title="Trade")
└── Body Column:
    ├── _AutoExecutionModeCard (Off | Paper | Live)   ← hoisted, always visible
    ├── Sub-tab strip (Live | Paper)                   ← view filter
    └── IndexedStack:
        ├── Live: original Live content (auto-mode card removed)
        └── Paper: PaperTradesPage
```

- Extract auto-execution mode card into private widget `_AutoExecutionModeCard` if not already
- Remove it from the Live sub-tab body
- Keep all existing state management, `AutoModeStatus` fetching, button onPress handlers

---

## Semantic distinction (preserve this)

| Control | Meaning |
|---------|---------|
| Sub-tab strip (`Live | Paper`) | **View filter** — which trades to display |
| Auto-execution mode card (`Off | Paper | Live`) | **Engine global setting** — what the engine should execute right now |

These are independent. The user can be viewing the Live trades sub-tab while the engine is set to Paper mode (or vice versa).

---

## Key files

| Path | Role |
|------|------|
| `lib/features/trade/trade_page.dart` | Main Trade tab — subject of in-flight PR |
| `lib/features/trade/paper_trades_page.dart` | Paper sub-tab body — **DO NOT TOUCH** |
| `lib/features/trade/paper_trade_detail_page.dart` | Paper trade detail — **DO NOT TOUCH** |
| `lib/data/repository.dart` | `AutoModeStatus` data class + API client |
| `lib/features/pulse/pulse_page.dart` | Has footer link added in #23 |

---

## Coding conventions

- 2-space indent
- `const` constructors wherever possible
- Private widgets extracted as `_WidgetName` in the same file (no separate files for small extracted widgets)
- No new dependencies without explicit approval

---

## Related backend work (mkmk749278/360-v2)

The backend is shipping `POST /api/auto-mode/paper/close-all` (see that repo's `docs/SESSION_HANDOFF.md`). If the next session wants a "Close all paper positions" button in the app, that's the endpoint to consume — likely surfaced on the Paper sub-tab body or as an app bar action when the Paper sub-tab is active.

---

## Open questions for next session

- Add a "Close all paper positions" button consuming the new backend endpoint? Where — Paper sub-tab body header, or app bar action?
- Should the auto-execution mode card collapse to a chip when scrolled, to reclaim vertical space?
