# Floating bar and General/Style options page: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Per-mode styling with LibSharedMedia fonts, a Bar Placement (On player frame / Floating) with a styleable floating bar as the fallback, and one Options page split into General and Style (Style shows only the selected mode's rows).

**Architecture:** One addon file (`ShiftingPowerCount.lua`) keeps its structure. Saved variables move style keys into per-mode sub-tables (`icon`, `text`, `bar`) behind a one-time migration; style reads go through `S(k)` (current mode's table). The floating bar is a second bar host beside the player-frame row, sharing `PlaceTicks`, the label pool and the OnUpdate value feed. The panel stays a single vertical Settings category with two section headers and shown predicates.

**Tech Stack:** Lua 5.1 (WoW Forever 1.60.1, Interface 16001), Blizzard Settings API, LibStub + CallbackHandler-1.0 + LibSharedMedia-3.0 (vendored), busted specs with the fake client in `spec/fake.lua`, luacheck, BigWigs packager.

**Spec:** `docs/superpowers/specs/2026-11-18-floating-bar-and-options-design.md` (owner-approved 2026-11-18, incl. "Calls made after the builder check").

## Global Constraints

- Never compare or compute on secret values (mana, percent, frame reads that may be secret): `issecretvalue()` first; never `a and b or c` on a possibly-secret value.
- Never write Blizzard frames' textures (PlayerFrame, PRD): only our own frames and textures.
- Anchor, parent or strata changes wait for `PLAYER_REGEN_ENABLED` (existing `pendingLayout`); plain values on our own frames apply live.
- Guard every divisor (the client raises on `x/0`).
- Every panel setting is reachable from `/spcount`, and panel and CLI write the same DB field.
- A v1.0.0 player's settings survive the upgrade (migration).
- `make check` green before every commit (luacheck 0 warnings, busted, tool tests). Commit trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Credit and licence for every vendored library (README credit + the library's licence file/note).

## Review Focus

1. **Upgrade from v1.0.0 with non-default settings** (font 2, colour 3, size 1.7, Dark bar style): every mode shows the same look as before. Test in Task 1 (`migration keeps a customised v1.0.0 look in every mode`).
2. **Switching Display or Placement in combat**: style rows switch at once, the frame change waits for combat end, no error. Test in Task 3 (`placement change in combat waits for combat end`).
3. **A stored LibSharedMedia name that is not registered** (ElvUI uninstalled): renders with the default, the stored name is kept. Test in Task 1 (`unknown font name renders the default and is kept`).
4. **Floating bar before max mana is known** (login in combat): empty bar, no ticks, no division. Test in Task 3 (`floating bar with unknown max shows empty, no ticks`).
5. **`/spcount fontsize 18` while Display = Number only** changes only the Number only style. Test in Task 2 (`style commands act on the current mode only`).

---

### Task 1: Vendored libraries, per-mode saved variables, migration, LibSharedMedia fonts

**Files:**
- Create: `Libs/LibStub/` , `Libs/CallbackHandler-1.0/`, `Libs/LibSharedMedia-3.0/` (copy from `~/src/hekili/src/Hekili/Libs/`, each with its licence file/note; verify the copies with `diff -r`)
- Modify: `ShiftingPowerCount.toc` (load `Libs\LibStub\LibStub.lua`, `Libs\CallbackHandler-1.0\CallbackHandler-1.0.xml`, `Libs\LibSharedMedia-3.0\lib.xml` before `ShiftingPowerCount.lua`), `.luacheckrc` (exclude `Libs/`; read global `LibStub`), `tools/check_package.sh` (require the three lib entry files), `ShiftingPowerCount.lua`, `README.md` (credit section)
- Test: `spec/fake.lua` (stub `LibStub("LibSharedMedia-3.0")`: `Fetch(type, name)` returning a path or the type's default, `List(type)`, `HashTable(type)`; fonts "Friz Quadrata TT", "Arial Narrow", "Morpheus", "Skurri"; statusbar "Blizzard"), `spec/migration_spec.lua` (new), `spec/options_spec.lua` (existing flat-key assertions move to the mode tables)

**Interfaces:**
- Produces: `MODE_KEY = { "icon", "text", "bar" }`; `MODE_DEFAULTS[modeKey][k]`; `S(k)` → value of `k` in the current mode's table, default from `MODE_DEFAULTS`; `SChoice(k)` (as `Choice` over `S`); `FontPath()` → `LSM:Fetch("font", S("font"))`; `Migrate(db)` (pure, testable); `Opt(k)` stays for General keys `mode`, `catOnly`, `prdTicks`, `locked`.
- Saved variables exactly as the spec's "Saved variables" section; `schema = 1`.

- [ ] **Step 1: Write the failing specs** in `spec/migration_spec.lua`:
  - `migration keeps a customised v1.0.0 look in every mode`: DB `{ mode=2, scale=1.7, iconAlpha=0.5, fontSize=24, font=2, outline=3, color=3, textPos=2, zeroRed=false, ticks=false, tickColor=2, barText=false, barColor=2, barStyle=3 }` → after login `icon` = `{scale=1.7, iconAlpha=0.5, fontSize=24, font="Arial Narrow", outline=3, color=3, textPos=2, zeroRed=false}`, `text` = same minus `iconAlpha`/`textPos`, `bar` has `font="Arial Narrow"`, `fontSize=24`, `ticks=false`, `tickColor=2`, `barText=false`, `barColor=2`, `barStyle=3`, `placement=1`; flat `scale`/`font`/`fontSize` are nil; `schema == 1`; `mode` still 2.
  - `fresh install gets defaults and schema 1` (no flat keys left behind).
  - `migration runs once`: a second login with `schema=1` leaves edited mode tables untouched.
  - `old dark boolean still maps to barStyle before migrating` (`dark=true` → `bar.barStyle == 3`).
  - `unknown font name renders the default and is kept`: `icon.font = "Gone"` → a label's `font[1]` is the stub's default path; `ShiftingPowerCountDB.icon.font == "Gone"`.
  - `the player-frame row caps the number at 14 without changing the stored size`: `bar.fontSize = 20`, mode bar → label font size 14, DB still 20.
- [ ] **Step 2: Run** `make test` → the new specs fail (no `schema`, flat keys).
- [ ] **Step 3: Implement.** `Migrate(db)` per the spec's Migration paragraph and calls 2 (font index map `1 "Friz Quadrata TT", 2 "Arial Narrow", 3 "Morpheus", 4 "Skurri"`); run it in `PLAYER_LOGIN` after the `dark` mapping, before defaults are filled into the mode tables. Replace style reads in `Style`, `Apply`, `TickLook`, `LayoutTicks`, `BarVisuals`, `ArtVisuals` with `S`/`SChoice`; fonts via `FontPath()`; remove `CHOICES.font` paths (fonts are names now). Keep the panel and CLI compiling against the new keys (minimal: register settings with the current mode's table; Task 2 rebuilds the panel).
- [ ] **Step 4: Run** `make check` → all green, including the updated existing specs.
- [ ] **Step 5: Commit** `feat: per-mode style tables with migration; LibSharedMedia fonts (vendored LibStub, CallbackHandler, LSM)`.

### Task 2: General and Style options page, CLI per mode

**Files:**
- Modify: `ShiftingPowerCount.lua` (`InitSettings`, `Set`, CLI tables, `USAGE`), `README.md` (Options and Commands sections)
- Test: `spec/fake.lua` (record section headers, `AddShownPredicate` per initializer, and `SettingsInbound.RepairDisplay` calls; initializers returned by `CreateCheckbox`/`CreateDropdown`/`CreateSlider` gain `AddShownPredicate`), `spec/options_spec.lua`

**Interfaces:**
- Consumes: `S`, `MODE_KEY`, `MODE_DEFAULTS`, `Opt` (Task 1).
- Produces: settings registered per mode table with variable names `SPC_<MODEKEY>_<KEY>` (General: `SPC_<KEY>`); `ModeShown(m)` predicate factory; `PlacementShown(p)`; `/spcount placement player|floating`, `width`, `height`, `texture <name>`, `bgalpha <0-1>`, `border on|off` keys reserved for Task 3 (registered there).

- [ ] **Step 1: Write the failing specs:**
  - `page has a General then a Style header`: headers in order `"General"`, `"Style"`, each with a non-empty tooltip.
  - `General rows are always shown`: `mode`, `catOnly`, `prdTicks`, `locked` controls have no predicate or a predicate that is true in every mode.
  - `Style shows only the selected mode's rows`: with mode 1 the `icon` rows' predicates are true and `text`/`bar` rows' false; `slash("mode text")` flips them; `RepairDisplay` was called.
  - `Bar rows follow Placement`: mode bar, placement 1 → `barColor`/`barStyle` shown, floating rows hidden; placement 2 → reverse; Frame tick colour option listed only for placement 1 (dropdown options differ or predicate).
  - `style commands act on the current mode only`: mode text, `slash("fontsize 18")` → `text.fontSize == 18`, `icon.fontSize` unchanged; the panel's text fontSize setting reads 18.
  - `reset and lock hidden for the player-frame row`: mode bar + placement 1 → their predicates false.
  - `font dropdown lists LibSharedMedia names`: options contain `"Arial Narrow"` and `"Friz Quadrata TT"`.
- [ ] **Step 2: Run** `make test` → the new specs fail.
- [ ] **Step 3: Implement** the page as the spec's layout: `CreateSettingsListSectionHeaderInitializer("General", tip)`, General rows, `"Style"` header, then each mode's rows registered against its own table with `AddShownPredicate(ModeShown(m))` (bar placement rows add `PlacementShown(p)`). Display and Placement callbacks call `SettingsInbound.RepairDisplay()` behind `if SettingsInbound and SettingsInbound.RepairDisplay`. Slider number boxes keyed per variable so two modes' "Number size" boxes don't collide. CLI style keys route to the current mode's table via `Set`.
- [ ] **Step 4: Run** `make check` → green.
- [ ] **Step 5: Commit** `feat(options): General and Style sections; Style shows only the selected mode; CLI style commands per mode`.

### Task 3: Floating bar, Placement and fallback

**Files:**
- Modify: `ShiftingPowerCount.lua` (floating bar host, `Layout`, `ApplyVisibility`, OnUpdate, `Rebuild`, `ResetPos`, drag, panel rows and CLI keys for the floating settings), `README.md`, `CHANGELOG.md`
- Test: `spec/fake.lua` (`CreateFrame` records the floating bar under a distinct name, e.g. `ShiftingPowerCountFloatingBar`), `spec/floating_spec.lua` (new)

**Interfaces:**
- Consumes: `PlaceTicks(host, list, show, w, h, frameArt)`, `S`, `SChoice`, the label pool and `Style`, `PlayerFrameUsable()`, Task 2's predicates.
- Produces: `floatBar` (StatusBar), `floatOn` flag beside `barOn`; `bar` table keys `placement`, `width` (default 150, 50-400), `height` (12, 4-40), `texture` (LSM default), `bgAlpha` (0.5, 0-1), `border` (true), `textPos` (Center/Left/Right/Above/Below); `barPos` top-level.

- [ ] **Step 1: Write the failing specs** in `spec/floating_spec.lua`:
  - `placement floating shows a bar of width x height with ticks per cost`: cost 400, max 2000, width 150, height 12 → tick x `{30, 60, 90, 120}`, cores sized `{2, 12}`; `SetValue` gets the secret on tick; min/max `0, 2000`.
  - `placement player with no PlayerFrame falls back to the floating bar`: `noPlayerFrame`, mode bar → floating bar shown, one chat line, icon frame not used for labels.
  - `placement change in combat waits for combat end`: combat on, `slash("placement floating")` → no re-anchor until `PLAYER_REGEN_ENABLED`, then floating bar shown.
  - `floating bar with unknown max shows empty, no ticks`: max 0 → no ticks, no error, bar min/max `0, 1`.
  - `texture, background, border and count position apply`: texture name → `SetStatusBarTexture` gets the stub path; unknown texture → default path, name kept; `bgalpha 0.2` → background alpha 0.2; `border off` hides the edge; `textPos` Left anchors labels LEFT.
  - `drag saves barPos; reset puts the floating bar back; lock stops dragging`.
  - `Frame tick colour is White on the floating bar`.
- [ ] **Step 2: Run** `make test` → the new specs fail.
- [ ] **Step 3: Implement** the floating bar per the spec's "Floating bar" section; `Layout()` realises `barOn` (placement 1 and PlayerFrame usable) or `floatOn` (bar mode otherwise); labels parent to the active bar's overlay; fill colour from `bar.barColor` preset as RGB (mana `0, 0.55, 1`, energy `1, 0.85, 0.1`, rage `1, 0.15, 0.15`, focus `1, 0.5, 0.25`, runic `0, 0.82, 1`); panel rows (Floating only) and CLI keys from Task 2's reserved list.
- [ ] **Step 4: Run** `make check` and `make package-check` from a plain clone tagged `v0.0.0-test` (the packager does not run in a worktree) → green, zip holds `ShiftingPowerCount/{.toc,.lua}` and `ShiftingPowerCount/Libs/...`.
- [ ] **Step 5: Commit** `feat(bar): Placement On player frame / Floating; styleable floating bar, used as the fallback`. README (Options, Commands, credit) and CHANGELOG (Unreleased) updated in this commit.
