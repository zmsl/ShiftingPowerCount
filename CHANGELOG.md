# Changelog

## Unreleased
- Bar mode has a Placement: On player frame (as before) or Floating, a movable, lockable bar you style (width, height,
  texture from LibSharedMedia, background opacity, border, count position, fill colour). When the player frame is hidden
  or replaced (ElvUI and the like) the floating bar is shown instead of the icon frame.
- The Options page has General and Style sections; Style shows the selected Display's rows; each Display has its own style.
- `/spcount placement|width|height|texture|bgalpha|border`; a style command for a mode other than the current Display
  says which mode it changed.
- Cast ticks on the Personal Resource Display's mana row (Cat and Bear Form), on by default in every display mode;
  `/spcount prdticks on|off` or the panel checkbox.
- Personal Resource Display ticks have their own section: shape Bar (width 1-8 px, default 2) or Pip (Blizzard's
  Cooldown Manager marker), coloured from a colour picker; `/spcount prdtickshape|prdtickcolor RRGGBB|prdtickwidth`.
- Colours are colour pickers: number colour (every display), bar tick colour (default black) and bar colour (Mana, or
  Custom with its own picker). The Frame tick colour is gone. Saved preset colours (v1.0.0) carry over as their exact
  colour; Energy, Rage, Focus and Runic power become Custom in that colour, and a Frame tick colour becomes black.
- The style section is titled after the selected Display: Icon Style, Number Style or Bar Style.

## v1.0.0
- First CurseForge release: live count of the Shifting Powers your mana pays for, in combat with secret mana; icon,
  number-only and player-frame bar modes with cast ticks; Cat Form only option; Options > AddOns panel and `/spcount`.
