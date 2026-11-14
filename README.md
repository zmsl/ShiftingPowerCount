# Shifting Power Count

Shows how many casts of Shifting Power (spell 1322605, WoW Forever Feral) your current mana pays for, as one number that stays correct in combat.

## Install

Copy or link this folder (`ShiftingPowerCount`) into the Forever `Interface\AddOns` folder. It needs only the `.toc` and `.lua`.

## Options

Options > AddOns > Shifting Power Count, or `/spcount` (opens the panel). Every change applies live, also in combat.

- Display: Icon and number, or Number only. (No "icon only": the number is the point of the addon.)
- Size: scales the whole frame (icon and number together), 0.5 to 3.0. The position is kept.
- Icon opacity, Lock position, Reset position button.
- Number size, font (Friz Quadrata, Arial Narrow, Morpheus, Skurri), outline (none, outline, thick), colour (white, yellow, green, cyan, orange), position (center, below, above the icon). All counts share these.
- Show 0 in red (on by default; off uses the number colour).

## Commands

- `/spcount` prints cost, max mana, casts at full and the main options, and opens the panel
- `/spcount size <0.5-3>`, `fontsize <8-72>`, `alpha <0-1>`
- `/spcount mode icon|text`
- `/spcount font frizqt|arialn|morpheus|skurri`, `outline none|outline|thick`, `color white|yellow|green|cyan|orange`, `pos center|below|above`
- `/spcount zero on|off`
- `/spcount lock` / `unlock` stops or allows dragging the frame
- `/spcount reset` puts the frame back at its default spot

Settings are saved in `ShiftingPowerCountDB`; the panel and the commands write the same fields.

## How it works with secret mana

Mana is secret in combat, so the addon never does arithmetic on it. It keeps one label per count, each with a step curve over mana percent that is 1 only inside its band, and `UnitPowerPercent(..., curve)` hands the secret result straight to `SetAlpha`. Cost and max mana are read out of combat and the bands are rebuilt. Option changes only touch plain values on the addon's own frame (scale, alpha, font, anchors).

## Tests

`busted spec` (fake client in `spec/fake.lua`).
