# Changelog

## v1.1.1
- Tick shape Frame: the experience bar's own divider, for the Personal Resource Display and the bar (player frame and
  floating). The bar's ticks now have Tick shape (Frame, Bar, Pip) and Tick width like the Personal Resource Display's;
  Bar and Pip show the colour picker. `/spcount tickshape|tickwidth`, `prdtickshape frame`.

## v1.1.0
- Bar mode has a Placement: On player frame (as before) or Floating, a movable, lockable bar you style (width, height,
  texture from LibSharedMedia, background opacity, border, count position). When the player frame is hidden or
  replaced (ElvUI and the like), Bar mode shows the floating bar instead of the icon frame.
- Cast ticks on the Personal Resource Display's mana row (Cat and Bear Form), in every display mode: shape Bar (width
  1-8 px, default 2) or Pip (Blizzard's Cooldown Manager marker), in a colour from a colour picker (default black).
- The Options page has a General section, a Personal Resource Display section, and a style section for the selected
  Display only (Icon Style, Number Style or Bar Style). Each Display keeps its own style.
- Colours are colour pickers: number colour (every display), bar tick colour (default black) and bar colour (Mana, or
  Custom with its own picker). The Frame tick colour is gone.
- Fonts come from LibSharedMedia, so fonts other addons register (ElvUI and media packs) can be picked.
- Your v1.0.0 settings carry over once into every display's style: preset colours become their exact colour; Energy,
  Rage, Focus and Runic power bar colours become Custom in that colour; a Frame tick colour becomes black.
- `/spcount` style commands act on the current Display; new `placement`, `width`, `height`, `texture`, `bgalpha`,
  `border`, `prdticks`, `prdtickshape`, `prdtickcolor`, `prdtickwidth`; colours take RRGGBB.
- Bundles LibStub, CallbackHandler-1.0 and LibSharedMedia-3.0 (credited in the README).

## v1.0.0
- First CurseForge release: live count of the Shifting Powers your mana pays for, in combat with secret mana; icon,
  number-only and player-frame bar modes with cast ticks; Cat Form only option; Options > AddOns panel and `/spcount`.
