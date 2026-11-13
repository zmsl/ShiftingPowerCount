# Shifting Power Count

Shows how many casts of Shifting Power (spell 1322605, WoW Forever Feral) your current mana pays for, as one number that stays correct in combat.

## Install

Copy or link this folder (`ShiftingPowerCount`) into the Forever `Interface\AddOns` folder. It needs only the `.toc` and `.lua`.

## Commands

- `/spcount` rebuilds and prints cost, max mana, casts at full and the percent scale
- `/spcount lock` / `unlock` stops or allows dragging the frame
- `/spcount reset` puts the frame back at its default spot

## How it works with secret mana

Mana is secret in combat, so the addon never does arithmetic on it. It keeps one label per count, each with a step curve over mana percent that is 1 only inside its band, and `UnitPowerPercent(..., curve)` hands the secret result straight to `SetAlpha`. Cost, max mana and the percent scale (1 or 100, derived from plain reads out of combat) are read out of combat and the bands are rebuilt.

## Tests

`busted spec` (fake client in `spec/fake.lua`).
