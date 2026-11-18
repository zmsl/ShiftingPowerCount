# Floating bar and a sectioned options page: design

Date: 2026-11-18. Owner-approved shape (conversation of 2026-11-18). Builds on PR #3 (`prd-ticks`: cast ticks on the
Personal Resource Display's mana row), which this work keeps and folds into the new page.

## Intent

Shifting Power Count shows how many Shifting Powers (Forever Feral, spell 1322605) the player's mana pays for. Two
problems with v1.0.0:

1. **Players on ElvUI-style UIs get no bar.** Bar mode attaches a fourth row to Blizzard's `PlayerFrame`. When another
   unit-frame addon hides or replaces it, Bar mode today falls back to the floating *icon* frame (one chat line), so
   those players can never have a bar.
2. **The options panel is one long undivided list** of ~20 settings, most of which only matter in one display mode.

## Goals

- Bar mode gains a **Placement** setting: **On player frame** (today's row) or **Floating** (a movable, lockable bar the
  player styles to fit their UI).
- When Placement is On player frame but `PlayerFrame` is unavailable, Bar mode shows the **floating bar** (not the icon
  frame); the one-time chat line stays and says so.
- One Options page (Options > AddOns > Shifting Power Count), standard Blizzard look: **section headers** (title, with
  the section's description in the header tooltip) split it into two sections: **General** and **Style**.
- **Style shows only the selected mode's rows** (owner decision); since only one mode's rows are ever visible, the
  section is simply titled "Style" (owner, 2026-11-18). Inside Bar, only the selected Placement's rows are shown.
- **Each mode has its own styling** (font, size, colour etc. are no longer shared between modes).
- Floating bar texture and fonts come from **LibSharedMedia-3.0**, so ElvUI's (and other packs') bar textures and fonts
  are available.

## Non-goals

- No tabs and no hand-built (canvas) panel. Tabs were considered and dropped by the owner in favour of the single
  native page.
- No bordered boxes: the native vertical list has no bordered container; section headers are the standard divider.
- No free colour pickers: colours stay preset dropdowns, like today.
- No change to how the count is computed (step curves over `UnitPowerPercent`, cost/max read out of combat).
- Player-frame bar visuals (atlas fill, mask, Match/Dark styles, Frame tick colour) unchanged.

## Anti-goals (failure even if it "works")

- Any arithmetic or comparison on secret values (mana, percent). The floating bar receives `UnitPower` via
  `StatusBar:SetValue` exactly like the player-frame bar does.
- Writing Blizzard frames' textures (PlayerFrame, PRD): only our own frames and textures are touched.
- Losing a v1.0.0 player's settings on upgrade.
- Settings that only `/spcount` can reach, or panel and CLI disagreeing.

## Constraints (verified in the Forever UI source, 2026-11-18)

- Settings API: `CreateSettingsListSectionHeaderInitializer(name, tooltip)` gives the header row.
  `initializer:AddShownPredicate(fn)` hides a row while `fn()` is false; `SettingsInbound.RepairDisplay()` makes the
  open panel re-evaluate after the predicate's inputs change (call it from the Display and Placement callbacks).
  Hidden rows are also skipped by Options search: search finds only the current mode's style rows. Accepted.
- `Settings.RegisterAddOnSetting(category, variable, key, tbl, vtype, name, default)` binds a setting to `tbl[key]`,
  so a per-mode sub-table works as `tbl`. Variable names must stay unique (`SPC_<MODE>_<KEY>`).
- In-combat rules stay as today: a change of anchor, parent or strata waits for `PLAYER_REGEN_ENABLED`; plain values on
  our own frames apply live.
- Lua 5.1, no `x/0` (the client raises): guard every divisor.

## Approaches considered

| | Approach | Trade-off | Outcome |
|---|---|---|---|
| A | Sub-pages per mode (Shifting Power Count > General / Icon / Number / Bar) | native, searchable; navigation in the left list | not chosen |
| B | One Style page with Blizzard's shared `TabSystemTemplate` tabs on a canvas layout, Blizzard widgets inside | tab look; no Options search, Defaults needs wiring, more code | chosen first, then dropped by the owner |
| C | **One native page, General + Style headers, Style shows only the selected mode's rows** | standard look, searchable, Defaults works; other modes' settings need a Display switch to see | **chosen** |

The floating bar was first proposed as its own fourth mode; the owner placed it inside Bar mode (Placement).

## Design

### Page layout (top to bottom)

```
── General ─────────────── (tooltip: what the addon shows; these apply to every mode)
  Display              Icon and number | Number only | Bar
  Show only in Cat Form
  Personal Resource Display: cast ticks
  Lock position        Reset position (button)
── Style ───────────────── (tooltip: how the selected display looks; switch Display above to style another mode)
  when Display = Icon and number:
  Size, Icon opacity, Number size, Number font, Number outline, Number colour, Number position, Show 0 in red
  when Display = Number only:
  Size, Number size, Number font, Number outline, Number colour, Show 0 in red
  when Display = Bar:
  Placement            On player frame | Floating
  Ticks, Tick colour, Show count, Number size, Number font, Number outline, Number colour, Show 0 in red   (both)
  Bar colour, Bar style                                                           (On player frame only)
  Width, Height, Texture, Background opacity, Border, Count position               (Floating only)
```

Each slider keeps its number box (today's `AttachBox`). Tick colour's Frame choice is offered only for On player frame
(it cuts the player frame's border art); on Floating and on the PRD it falls back to White as PR #3 does.

### Saved variables

`ShiftingPowerCountDB` gains a `schema` number and per-mode sub-tables; account-wide as today:

- top level (General): `mode`, `catOnly`, `prdTicks`, `locked`, `pos` (floating icon/number frame), `barPos` (floating bar).
- `icon`: `scale`, `iconAlpha`, `fontSize`, `font`, `outline`, `color`, `textPos`, `zeroRed`.
- `text`: `scale`, `fontSize`, `font`, `outline`, `color`, `zeroRed`.
- `bar`: `placement` (1 player frame, 2 floating), `ticks`, `tickColor`, `barText`, `fontSize`, `font`, `outline`,
  `color`, `zeroRed`, `barColor`, `barStyle`, `width`, `height`, `texture`, `bgAlpha`, `border`, `textPos`.

Fonts are stored as LibSharedMedia **names** (strings), in every mode, so one font list serves all modes.
LibSharedMedia registers Friz Quadrata, Arial Narrow, Morpheus and Skurri itself, so the four v1.0.0 fonts keep working.

**Migration** (once, when `schema` is absent): copy today's flat keys into each mode's table where the key exists there
(`scale`, `iconAlpha`, `fontSize`, `font`→name, `outline`, `color`, `textPos`, `zeroRed`, `ticks`, `tickColor`,
`barText`, `barColor`, `barStyle`), set `bar.placement` = 1, drop the flat keys, set `schema = 1`. Keep the existing
`dark`→`barStyle` migration ahead of it. Bar `fontSize` is still capped at 14 on the player-frame row.

### Floating bar

- A `StatusBar` of our own, parented to `UIParent`, movable by drag when unlocked, clamped to screen, position saved
  in `barPos`; default spot below screen centre.
- Fill: LibSharedMedia `statusbar` texture (`bar.texture`, default LibSharedMedia's default), coloured by `bar.barColor`'s
  preset as an RGB (mana blue, energy yellow, rage red, focus orange, runic cyan: the same five presets).
- Background: a texture behind the fill, black at `bar.bgAlpha` (default 0.5). Border: a 1px black edge on/off
  (`bar.border`, default on).
- Size: `bar.width` (default 150, range 50-400), `bar.height` (default 12, range 4-40).
- Ticks: the shared `PlaceTicks` over width x height, one per cost, as on the other bars.
- Count: the same per-count labels on an overlay above the fill; `bar.textPos` Center / Left / Right / Above / Below.
- Values: `bar:SetValue(UnitPower("player", MANA))` in the existing throttled OnUpdate; min/max from out-of-combat max mana.

### Fallback and visibility

- Display = Bar and Placement = On player frame and `PlayerFrame` unusable → floating bar (chat line once).
- Cat Form gate, spell-known gate and PRD ticks behave as today across all modes.

### CLI

Every panel setting stays reachable. General keys keep their commands (`mode`, `catonly`, `prdticks`, `lock`,
`unlock`, `reset`). Style commands act on the **current mode's** table (`/spcount fontsize 18` sets the font size of
whatever Display is selected), plus `placement player|floating`, `width`, `height`, `texture <name>`, `bgalpha`,
`border on|off`. `reset` resets the position of the frame the current mode shows. Font and texture arguments are
LibSharedMedia names (case-insensitive match).

### Library

Vendor **LibStub** and **LibSharedMedia-3.0** under `Libs/`, loaded from the TOC before the addon file, with their
licence files and a README credit (project rule: reuse reputable libraries, vendor with licence and credit). Fetched
with the `.pkgmeta` externals mechanism or committed; builder's call, but the CurseForge zip must contain them
(`tools/check_package.sh` checks).

## Left to the builder

- Internal code structure (how Style/Layout/Apply split per mode), tick/label host reuse.
- Exact border drawing, default texture choice, label offsets for Above/Below/Left/Right.
- Whether panel dropdowns for fonts/textures list LibSharedMedia's entries at panel build time (acceptable) or rebuild
  on open.
- Spec coverage: migration, shown predicates per mode/placement, floating bar ticks/value/fallback, CLI per-mode routing.

## Calls made after the builder check (2026-11-18)

Marked as the designer's calls, not owner decisions; the owner reviews them with this document.

1. **Bar placements share one style.** On player frame and Floating both read `bar.*` (font, size, outline, colour,
   0-in-red, ticks, tick colour, show count): Placement is a sub-choice of one mode. Label hosts and pools are left to
   the builder.
2. **The 14 cap is applied at render time, on the player-frame row only.** The stored `bar.fontSize` is never clamped,
   so a migrated 20 shows as 14 on the row (as today) and as 20 on the floating bar. Bar mode has no `scale` on
   purpose: the floating bar is sized by width and height. Migration maps the v1.0.0 font index to a name:
   1 Friz Quadrata, 2 Arial Narrow, 3 Morpheus, 4 Skurri.
3. **Missing LibSharedMedia names** (a media pack uninstalled): render with LibSharedMedia's default font/statusbar for
   that type, keep the stored name (so it comes back when the pack returns). The dropdown lists what is registered at
   panel build time; a stored name not in it shows as LibSharedMedia's default.
4. **Unknown max mana:** as today: no labels shown until the first out-of-combat rebuild; the floating bar shows empty
   (min/max 0..1) and no ticks. `PlaceTicks(host, list, show, w, h, frameArt)` already takes width and height (PR #3).
5. **Downgrade to v1.0.0 and back:** accepted risk; flat keys v1.0.0 writes are ignored once `schema` is 1.
6. **Reset position** acts on the frame the current mode shows (icon/number frame, or floating bar). The panel button
   and `Lock position` are hidden while Display = Bar and Placement = On player frame (nothing to move).
7. **Libraries are committed** under `Libs/` (no `.pkgmeta` externals), so a dev checkout and CI have them; specs stub
   `LibStub("LibSharedMedia-3.0")` in `spec/fake.lua` (Fetch/List/HashTable) rather than loading the real library.
8. **Shown predicates read `ShiftingPowerCountDB`** (`mode`, `bar.placement`) directly; the Display and Placement
   callbacks call `SettingsInbound.RepairDisplay()` behind a nil-guard.
