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

## Round 2: conveyor, placement, items and roll reveal

- **Placement:** the inventory Place button and area picker are gone; players place by
  clicking a conveyor slot (or the machine on it). Area text labels above the belt are
  removed. Each slot has an invisible `SlotSelector_n` click plate flush with the belt,
  and the client draws a translucent selection box: faint and softly pulsing on empty
  slots, amber while hovered or while that slot's placement panel is open.
- **Conveyor:** one continuous rubber belt between two drums on a low base that rests on
  the ground (no legs), steel side rails rising from the ground with a light lip, an amber
  safety stripe (coral at the seller bay) and rail bolts. Client-only cleats ride every
  nearby belt toward the seller at item speed (`ConveyorController`, one 30 Hz
  `BulkMoveTo` loop). Items and machines follow the lower belt through the shared
  geometry, and the build uses fewer parts than before.
- **Fonts:** every UI string uses `FontFace` from `HudTheme`: Fredoka One for headings
  and numbers, Nunito for text (also on machine badges and booster labels).
- **Items:** produced cubes use SmoothPlastic; the cube tooltip shows a type dot and
  name, a chain chip, a coin icon with the sale value and the upgrade/sale breakdown;
  sale popups show a coin icon and the amount; booster drops get a two-line glass pill.
- **Roll reveal (`RollRevealController`):** blurred, dimmed stage with a virtualised reel
  of rarity-tinted machine cards (weighted by the real roll chances) that spins while the
  server answers, eases onto the result under a centre marker and pops the landed card.
  A result card follows with a rotating 3D preview, rarity title, name, rarity/odds/
  category chips and description. Rare+ adds rotating light rays, Epic+ sparkles, and
  ultra-rare odds a colored flash and a longer hold. Click skips the spin or dismisses.

## Round 3: floor drops and saved factories

- **Floor drops:** booster drops land as glowing, slightly turned cubes. Their name pill
  no longer floats over every drop; the client shows it only while the drop is hovered
  with the mouse or tapped on touch.
- **Saved factories:** placed layouts previously reset on rejoin whenever a slot before
  the seller bay was empty, because data stores drop array entries after a `nil`, which cut
  the seller off the saved layout and failed validation. Layouts are now stored as five
  strings (`""` for empty) on every save and on session acquisition
  (`SaveSchema.toStorage` / `sanitizeForStorage`). A saved layout that is still unusable
  falls back to the default route and returns its rollable machines to inventory.

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

- Round 2 visuals in a live session: conveyor look and cleat direction on rotated
  plots, selection-box hover/selected states with mouse and touch, the reel spin and
  landing feel, result card readability on phones, and frame time with six plots.
- Font families (`Nunito`, `FredokaOne`) are built-in Roblox fonts; confirm rendering.
- Audio for roll ticks and reveal is not added; Phase 9 still requires licensed sounds.

- Round 3 live check: place machines with an empty slot before the seller, rejoin, and
  confirm the layout returns; hover and tap a floor drop to see its label.

## Incomplete / Needs Work

- Broader Phase 9 items (audio, onboarding playtests, balance) remain open; this
  change only replaces the UI presentation.
