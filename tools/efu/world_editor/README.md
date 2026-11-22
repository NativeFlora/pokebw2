# Escape from Unova world editor

Edits the hack's maps from above like a paint program: select, move, copy and paste pieces of a map, paint and erase,
on whichever layers are ticked (ground, props, collision, tile class, events). It places props, boulders, Cut trees,
item balls, people, doors, signs and triggers, and its door panel sets where a door leads and whether it is locked and
with which key. It saves `world_edits.json`, which `tools/efu/apply_world_edits.py` writes into `res/` for the build.

## Using it (Windows)

1. Unzip `world-editor.zip` anywhere, for example `F:\Romhacks\Escape from Unova\world-editor\`.
2. Open `index.html` in Chrome or Edge (double-click, or drag it onto the browser). Nothing to install.
3. Edit. **Save edits** (Ctrl+S) asks where to save the first time: save `world_edits.json` in the same folder,
   replacing the one there. Later saves go to the same file.
4. Tell Claude the edits are saved. Claude picks up the file, applies it and builds the ROM.

Unsaved work is kept in the browser and offered back the next time the editor opens.

## Moving around

- Pick a map at the top. The hack's maps come first; `OVERWORLD_2 (copy from)` is the whole of Unova, there only to
  copy from.
- Wheel: zoom at the cursor. Right-drag, middle-drag or Space+drag: pan.
- **3D** shows the map at an angle (orbit with the mouse); editing is in the top-down view.
- The status bar shows the tile under the cursor: its place, chunk, model, zone, class, whether it's blocked, and its
  height.

## Layers

The **Layers the tools change** list says what the Rectangle, Brush (pattern) and Eraser tools touch. Tick **All** to
change everything at once. Alt+1 to Alt+5 toggle them one by one, Ctrl+A ticks them all.

| Layer | What it is |
| --- | --- |
| Ground | The map's geometry (grass, paths, trees, cliffs, water) and the tiles' heights |
| Props | Field props: buildings, doors, fences, signs, fountains... |
| Collision | Whether each tile is blocked (the red overlay), and its other flags |
| Tile class | Each tile's class: grass, ledge, water, stairs... (the Tile classes overlay) |
| Events | NPCs, objects (boulders, Cut trees, item balls), warps, triggers and signs |

## Tools

| Key | Tool | What it does |
| --- | --- | --- |
| V | Select | Click an event or a prop (orange diamond) to see and edit it in the inspector; drag it to move it. Click a tile to see and set its class and flags. Delete removes the selected thing. |
| R | Rectangle | Drag to select. Drag inside the selection to move it (what it leaves behind is erased). Ctrl+C copies, Ctrl+X cuts, Ctrl+V then a click pastes (Shift+click to paste again), Delete erases, Esc lets go. A selection on another map, or the overworld, copies from there. |
| B | Brush | Block, Unblock, Tile class or Pattern, at 1×1 to 8×8. Pattern paints with a copied rectangle, tiled like wallpaper, or with one tile picked by Alt+click: grass, path, forest. Alt+click in Tile class mode picks a class. |
| E | Eraser | Drag to erase the ticked layers: the ground's trees and cliffs go and the **Lay ground** material is laid flat; props go; collision clears; the class becomes the nearest walkable tile's; events go. |
| P | Insert | Pick from the box: objects (Strength boulder, Cut tree, item ball, person, door, sign, trigger) or the area's props, with pictures, then click to place. Q turns a prop 90°. "Block the tiles under a prop" blocks its footprint. |
| K | Chunk | Click a chunk to set its map model and zone. |

Ctrl+Z undoes, Ctrl+Y redoes, Ctrl+S saves.

## Doors

Selecting a warp, or a door prop with a warp on or beside it, opens the door panel:

- **Leads to** and **Its door**: the zone and which of its warps the player comes out at. **Show its door** jumps
  there; **Make it two-way** points that door back at this one.
- **Arrive facing**: the way the player faces on arriving through this warp.
- **Locked**: the door says it is locked when walked into. With a **Key item** it opens for good once the player has the
  item (**Uses up the key** takes it away); without one it never opens. **Locks again each raid** shuts it again every
  time the player heads out. A padlock marks locked doors on the map.

A door prop without a warp gets a **Make it a door** button, which puts a warp on its tile.

## Good to know

- Trees stand in rows two tiles apart. When moving or pasting forest, move by an even number of tiles, or the rows
  won't line up. A 2×2 forest pattern brush stays in step by itself.
- A warp leads to another zone's warp **by its number in that zone's list**. Deleting a warp renumbers the ones after
  it, so the editor asks first. Warps added go at the end.
- "Heights follow ground" sets an event's height from the ground when it is moved or added.
- The overlay shows collision (red) or tile classes (green grass, blue water, orange ledges with a dot on the side
  you jump to, pink one-way walls, cyan furniture).
- Props belong to their area's prop set, so a prop can only go on chunks of the same set; the Insert box lists the
  sets of the map shown, the one under the cursor first.
- An item ball runs the loot script. Give it a free event flag (in its fields) to keep it taken once picked up.

## For Claude: the pipeline

- `python3 tools/efu/world_editor/export_pack.py [OUT_DIR]` applies the saved edits to `res/`, then writes the editor
  (`web/index.html`, `web/editor.js`) with the maps as `pack/` (default `build/world_editor/`). Zip that folder for
  Tom. `web/build.sh` rebuilds `editor.js` from `web/src/` (needs Node; the bundle is committed).
- `python3 tools/efu/apply_world_edits.py` (from `tools/efu`, after `build_raid.py`) applies `world_edits.json`; it is
  idempotent. Each edited chunk becomes its own model (`MAP_MODEL_EFU_EDIT_*`), rebuilt from its base each run, with
  the bases in `world_edit_bases.json`.
- Edits are operations in order, each on the world as the ones before left it (the docstring of
  `apply_world_edits.py` lists them; `web/src/engine.js` and `geometry.js` do the same in the editor). An event is
  found by all of its fields, so if `build_raid.py` changes an event that an edit changes too, the edit is skipped with
  a note: check its output.
- Locks: `apply_world_edits.py` numbers them in `world_locks.json` (never reused: saves keep their flags), puts the
  number in the warp's `grid.unk0a` and a sign with the lock's script on its tile; `gen_efu.py` writes the scripts.
  The game's side is `Efu_IsShutDoor` in `src/ov036/fieldmap_event.c` and `EFU_FLAG_LOCK_FIRST` in `include/efu.h`.
