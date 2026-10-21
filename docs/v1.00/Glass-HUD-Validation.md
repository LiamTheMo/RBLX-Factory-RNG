# Glass HUD validation

The Figma raster HUD (`AmberUI`, `AmberLayout`, the four uploaded sprite sheets and
the unused `DebugHudController`) is removed. Every player-facing screen element is
rebuilt as a code-only, semi-transparent glass interface:

- `src/shared/HudTheme.luau` — shared palette, transparency, radius and font tokens
  (also used by the server-built booster world label).
- `src/shared/HudLayout.luau` — pure safe-area geometry for desktop, landscape phones
  and portrait screens; covered by `tests/HudLayout.spec.luau`.
- `src/client/Controllers/GlassUI.luau` — glass panels, pill buttons with hover/press
  feedback, chips and frame-drawn icons (coin, dice, box, sliders, close). No image
  assets, so Studio and live servers render identically without asset permissions.

| Surface | Location | Notes |
| --- | --- | --- |
| Coins pill | top left | Live balance, pulse on income, active Luck / Coins booster chips below |
| Settings | top right (beside Coins on landscape phones) | Factory slots, machines owned, save state, capacity purchase |
| Inventory button | bottom left | Owned-count badge; icon-only on compact screens |
| Roll button | bottom center, kept clear of the open drawer | Ready / cooldown progress / rolling / loading states |
| Inventory drawer | right side (bottom sheet on portrait) | Droppers / Upgraders / Sellers / Boosters tabs, rarity-tinted cards with live model previews |
| Roll reveal | full screen | Dim overlay, camera blur, glass card with rarity-colored rim |
| Toasts | below the Roblox top bar | Glass pill with colored accent dot |
| Cube tooltip, sale popups, booster labels | world | Restyled to the same palette |

The inventory drawer now starts closed on join so the Roll button is the first call to
action; it opens from the Inventory button or by clicking a conveyor area.

Server authority is unchanged: placement, move, return, recycle, booster use, capacity
and free rolls still go through the existing validated remotes.

## Completed / Passed

- Luau compilation, all pure Luau suites (including the new layout spec across eleven
  desktop, landscape and portrait viewports), Python tests, GLB manifest validation,
  code-mapping checks and Rojo build.
- Layout spec: no HUD control overlaps another control or the open drawer; every
  control stays inside the safe area; settings, inventory and roll keep a 44px touch
  target; content scale never drops below 0.8.
- Studio smoke harness (`tests/studio/PrototypeSmoke.luau`) updated to the new UI tree.

## Requires Manual Validation

- Owner visual acceptance on desktop and physical phones (readability, touch feel,
  glass contrast over bright water and sand).
- Run the updated Studio smoke harness against a Rojo-built place.
- Studio-authored UI: the publisher only syncs Git-managed scripts. Any ScreenGuis
  placed by hand in the live place's `StarterGui` are not visible from the repository
  and must be removed in Studio if they should go too.
- Orphaned script modules: the publisher never deletes instances, so the old
  `AmberUI`, `AmberLayout` and `DebugHudController` ModuleScripts stay in the live
  place. Nothing requires them, so they create no UI; remove them in Studio when
  convenient.

## Incomplete / Needs Work

- Broader Phase 9 items (audio, onboarding playtests, balance) remain open; this
  change only replaces the UI presentation.
