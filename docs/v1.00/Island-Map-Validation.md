# Workshop Amber island map

## Scope

Reference images 4 and 5 guide the map: cheerful grass, sandstone coast,
timber workshops, garden vegetation and docks. Images 1–3 are the Workshop
Amber UI reference sheets; their palette informs lantern and timber accents.
This change implements the map and factory integration, not a UI replacement.

`IslandWorldBuilder` creates editable native Roblox parts without external
mesh loading. Six starter islands surround a three-tier central mesa, with
a large treehouse, two cave shelters, decorative crystals and a waterfall.
Boardwalks connect the islands; ramps reach the treehouse deck. Each starter
island has a cabin, garden terrace, flowers, trees, dock and clear factory area.

`IslandWorldConfig` is the source of truth for map identity, ground/water
height, six plot positions and free-island allocation. The server assigns
and releases islands, sets the player's respawn location, and returns players
who fall below the lagoon to their own island. The existing five-slot route,
inventory, payouts and save schema remain intact. Configure the Roblox place
for six players; a seventh player is redirected by a full-server kick message.

The map is constructed before the gameplay services start. Studio edit mode
can preview it by requiring `IslandWorldBuilder` and calling `build()` through
the Studio MCP. Rojo builds include the source; map generation occurs at
runtime. The model is named `WorkshopAmberIslands` and uses stable island names.

## Low-poly island map (revision 2)

The owner chose to replace the native-part islands with the imported low-poly
island model: six copies on the plot ring, plus a central hub reached by parkour.
The hub model is not built yet.

**Template.** `IslandWorldBuilder` looks for `ServerStorage.IslandAssets.TinyFactoryIsland`.
The scripts-only publisher never touches that container, so the imported model
survives deploys.
- **Pivot convention:** X/Z is the factory clearing centre, Y is the waterline,
  and the rotation is yaw only, with +X running along the conveyor.
- **`GroundHeight` attribute:** the clearing's height above the waterline. The
  builder warns if it differs from `IslandWorldConfig.Templates.GroundHeight`
  (9.0 studs).
- **Hub:** an optional `TinyFactoryHub` model follows the same convention. Until
  it exists, a placeholder rock-and-lawn hub is built.
- **Fallback:** without the island template, the original native map is built.

**Layout.**
- The plot ring radius is 230 studs. Imported islands reach up to about 106 studs
  from their pivot, so neighbours keep at least 18 studs of open water.
- Each plot is rotated so its conveyor runs tangent to the ring. The six conveyors
  frame the hub like the sides of a hexagon, and each runs left to right for a
  player facing the hub.
  - `IslandWorldConfig.getPlotAxis` gives each plot's conveyor direction.
  - `FactoryService` builds the factory axis-aligned, then swings it into the
    plot frame. Items and loot raycasts use that frame.
  - The island template is rotated to match.
- `GroundY` is derived as water + lift + ground height, giving 7.15.
- Each island's `IslandSpawn` comes from an optional `SpawnAnchor` part, or sits
  12 studs off the conveyor.
- Players are placed there on join. Falling into the lagoon (below
  `FallRecoveryY`, -1) sends them home.

**Parkour.** The lagoon is "noise": loose rocky islets, stepped rock clusters and
small grassy islands, all modeled to match the island, scattered everywhere at
widely varying heights with no visible paths. Players work out their own way to
the hub or to other islands.
- **Noise field:** `ParkourLayout.field` (a pure module) scatters about 170
  groups over the whole lagoon. Each group is one of three kinds:
  - a small island (`Isle_*`, about 12%, at most 10);
  - a stepped cluster of 3–5 fused stacks (`Cluster_*`, about 30%);
  - otherwise 1–5 loose islets whose tops range from 6 to 11 studs, skewed small.
- **Heights:** each group sits at `Config.landingHeight` (island ground on the
  ring, rising to the hub) ±6 studs. Loose islets within a group differ by up to
  3.5 more, and clusters are stretched so their lowest step lands at the group's
  height. Tops range from about 2 to 16 studs above the water.
- **Footprints:** islet, cluster and island bases keep open water between them.
  Around each island the keep-out is a fan of circles fitted to the shoreline
  measured at 48 bearings, so rocks can sit right against the coast instead of
  leaving a ring of empty water.
- **Reachability:** a one-way jump graph links every walkable top. Climbs are
  limited to 4 studs, drops to 14, and gaps to 8.
  - Islands join the graph at plateau ledges (24 bearings, ground mesh only) and
    at the far end of their dock.
  - Only where an island cannot reach the hub (or the hub an island) does the
    layout add bridge rocks, linking to the nearest unreached group in short
    hops steered toward the goal.
  - Bridge rocks wander up to 0.9 rad off course, mix sizes and heights, keep
    clear of shores and other rocks, and some have dead-end side rocks, so they
    read as more scattered rocks rather than a line. A straight zigzag is used
    only if the lagoon is too crowded to wander.
  - Result (seed 7): 262 pieces (206 islets, 46 clusters, 10 small islands) with
    466 walkable tops, 60 of them bridge or side rocks. Bounded to 320 pieces
    and 60 repairs; the field computes in under a second.
  - The builder warns if anything is ever left unreachable.
- **Lagoon models:** `ServerStorage.IslandAssets.Islets` holds `Islet_*` Models
  (with a `TopHeight` attribute in studs above the waterline), `Cluster_*` and
  `Isle_*` Models, and `Boulder_*` Models, all pivoted at their waterline centre.
  `src/shared/IsletCatalog.luau` lists every cluster's and island's walkable
  tops. It is generated by `tf_islets_build.py`, which also exports the FBX, so
  the layout knows exactly where players can land.
- **Placement:** each islet uses the shortest variant that reaches its height,
  scaled across to its size and sunk until its grass top lands exactly on that
  height. Low islets keep their proportions instead of being squashed; only spots
  above the tallest variant are stretched. Clusters and islands are yawed and
  scaled about their pivot exactly as the layout computed their tops.
- **Foam:** every lagoon model's foam is traced from the rock's actual waterline
  outline, the same way as the island's: a bright rim with broken froth beyond
  it and a thin turquoise shallow-water halo. It stays flat on the water.
- **Footings:** rock bases reach about 13 studs under the water, onto deep
  footings in the floor's colour.
- **Fallback:** placeholder rock columns are used until the islets are imported.
  A missing cluster or island model falls back to loose islets on its tops.

**Lagoon rocks.** About 60 decorative boulders are scattered through the lagoon so
it reads as a natural rocky sea.
- The scatter is seeded and bounded, with a 16-stud spacing.
- It stays 8 studs off every measured shore and 12 studs from every lagoon piece.

**Visiting.** Visitors can now reach other players' plots. Booster drops
(`LootService.claim`) are claimable only by the plot owner, which closes an
existing audit finding that visiting would have made exploitable.

**Water surface (preferred).** The lagoon matches the Blender preview water: parts
covering the water area, textured with a seamless 1024 px tile baked from the preview
material's colours and caustics (`tf_water_texture_bake.py` →
`textures/roblox_water_surface_1024.png`).
- Over the lagoon floor the base layer is 30% see-through, so the sand shelves,
  deep floor and rock bases show faintly. Beyond the floor it is opaque. The
  Terrain floor (no Terrain water) is built underneath.
- A second, translucent layer at another scale sits on top. `CausticsController`
  drifts the two layers in different directions every frame, from one
  RenderStepped connection, so the motion is smooth rather than stepped.
- The surface is 4800 studs across (16 parts), so its edge never shows, even from
  high cameras. Every part is a whole number of tiles wide, so there are no seams.
- The base layer is tinted slightly bluer, and the haze decays far water to a deeper
  blue, so distant water does not read as flat neon cyan.
- The image must be owned by the place's group: upload it with Studio's Asset
  Manager import and set `Water.Surface.TextureId`. The earlier caustics image
  never loaded because it is owned by a user account, not the group.
- With no `TextureId`, the Terrain water below is the fallback.

**Water (Terrain fallback).** Runtime Terrain water covers 2400 × 2400 studs. Atmosphere haze, in the
water's colour, fades its far edge into the sky.
- Colour (18, 128, 168), transparency 0.7, wave size 0.15 and wave speed 10 give
  a deeper teal with visible moving ripples.
- Sand shelves around every island and the hub sit 6 studs under the surface,
  so the shallows read turquoise. Two terraces, each 4 studs deeper and 22 studs
  wider, fade them out instead of ending at one hard edge.
- Between land, the floor is dark (Mud, coloured deep blue-green, 18 studs
  down), so open water reads deep blue.
- Every floor top sits on a 4-stud voxel-layer boundary. A partly filled layer
  near the surface renders as blocky sand squares reaching up to the water.
- Lagoon rock footings sit about 10 studs down in the floor's colour, so they
  never show near the surface.
- An optional caustics `Texture` layer (`CausticsTextureId`) is scrolled by
  `CausticsController` at 10 Hz.

### Revision 2 validation
- 11 Luau suites pass. They include the new `tests/parkour_layout.luau` and an
  extended `tests/island_world.luau`.
- `tests/parkour_layout.luau` checks:
  - jump limits on routes;
  - the noise field on the measured island profile: two-way reachability for
    every island, climbable cluster steps, a mix of islets, clusters and small
    islands, height spread, quadrant spread, no overlaps, bounded bridges and
    determinism;
  - the boulder scatter: bounded, clear of keep-out areas and spaced.
- `tests/island_world.luau` checks conveyor/centre coupling, island spacing for
  the imported footprint, heights and the fall threshold.
- `luau-analyze` is clean on the shared layout, catalog and config modules.
- Luau compile of `src` and `tests`, and the Rojo build with module checks, pass.
- Python unittests were not run locally (no Python on the dev machine); they
  are untouched by this change.
- Still requires Studio: template pivot set-up, a playtest of placement, spawn,
  parkour completion, fall recovery and water look, six-player load, and
  device frame time.

## Completed / Passed (revision 1, native map)

- Read all 42 Markdown files present before this change.
- Nine Luau suites, including island separation, full-capacity handling and
  released-slot reuse.
- Luau source/test compilation.
- Seventy-two source GLB validations and seven Python import-helper tests.
- Rojo place build and diff whitespace review.
- Inserted the map into the user-confirmed Studio place 116499398973334.
- Studio server smoke: 150 ground samples, 4,468 anchored map parts, assigned
  island respawn, character reload, lagoon fall recovery and nine completed sales.
- Studio pathfinding: all six island-to-hub routes and all seven boardwalk/ramp
  segments leading to the treehouse deck succeeded.
- Removed the temporary server QA script after the test. The repeatable source
  remains in `tests/studio/IslandMapSmoke.server.luau`, outside the Rojo game tree.
- Inspected Studio screenshots of the world and a starter island. Invisible
  collision strips bridge wedge seams; elevated access routes avoid solid cliffs
  and the central trunk.

## Requires Manual Validation

Studio engine and pathfinding checks passed on 2026-10-10. These are automated
Studio checks, not owner visual acceptance or device/multiplayer measurements.

- Owner visual acceptance of shores, gardens, tree silhouettes and map scale.
- Human walkthrough of every boardwalk/ramp and cabin/cave shelter.
- Check factory ground elevation, plot camera clearance and all five click areas.
- Test reconnect and initial spawn on a fresh published server.
- Check six simultaneous players, one departure and slot reuse by a new player.
- Run the updated Studio smoke test on a built local place.
- Measure construction time, frame time and memory on desktop and phone/tablet.
- Confirm published main validation and deployment before deployed acceptance.

## Incomplete / Needs Work

Visual acceptance, device profiling and deployed acceptance remain open. UI atlas
integration, machine art and audio stay in their separately documented MVP phases.
