# Escape from Unova world editor

Edits the hack's maps from above: collision and tile types, NPCs, warps, triggers and signs, which model and zone each
chunk of a map is, and the ground itself (clear an area, or stamp a piece of another map over it). It saves
`world_edits.json`, which `tools/efu/apply_world_edits.py` writes into `res/` for the build.

## Using it (Windows)

1. Unzip `world-editor.zip` anywhere, for example `F:\Romhacks\Escape from Unova\world-editor\`.
2. Open `index.html` in Chrome or Edge (double-click, or drag it onto the browser). Nothing to install.
3. Edit. **Save edits** (Ctrl+S) asks where to save the first time: save `world_edits.json` in the same folder,
   replacing the one there. Later saves go to the same file.
4. Tell Claude the edits are saved. Claude picks up the file, applies it and builds the ROM.

Unsaved work is kept in the browser and offered back the next time the editor opens.

## Moving around

- Pick a map at the top. The hack's maps come first; `OVERWORLD_2 (copy from)` is the whole of Unova, there only to
  stamp from.
- Wheel: zoom at the cursor. Right-drag, middle-drag or Space+drag: pan.
- **3D** shows the map at an angle (orbit with the mouse); editing is in the top-down view.
- The status bar shows the tile under the cursor: its place, chunk, model, zone, class, whether it's blocked, and its
  height.

## Tools

| Key | Tool | What it does |
| --- | --- | --- |
| V | Select | Click an NPC, warp, trigger or sign to edit its fields in the inspector; drag it to move it. Click a tile to see and set its class and flags. Delete removes the selected event. |
| B | Collision | Drag to block tiles; Shift+drag to unblock them. |
| C | Tile class | Drag to paint the chosen class (grass, ledge, water...). Alt+click picks a tile's class. |
| X | Clear | Drag a rectangle: everything on it goes (trees, rocks, props, the ground), grass is laid flat at the height around it, and its tiles copy the nearest walkable tile. For cutting paths and openings. |
| S | Stamp | Drag a rectangle inside one chunk to copy it (geometry, props and tiles), from this map or another, then click where its top left goes. Shift+drag copies another; Esc drops it. For closing a road with forest, or bringing in a path, a ledge or a patch of grass. |
| M | Chunk | Click a chunk to set its map model and zone. |
| N W T G | Add | Click a tile to add an NPC, warp, trigger or sign to the zone there, then fill in its fields. |

Ctrl+Z undoes, Ctrl+Y redoes.

## Good to know

- Trees stand in rows two tiles apart. When stamping forest, copy from and place at the same column and row parity
  (an even tile to an even tile), or the rows won't line up.
- A warp leads to another zone's warp **by its number in that zone's list**. Deleting a warp renumbers the ones after
  it, so the editor asks first. Warps added go at the end.
- "Heights follow ground" sets an event's height from the ground when it is moved or added.
- The overlay shows collision (red) or tile classes (green grass, blue water, orange ledges with a dot on the side
  you jump to, pink one-way walls, cyan furniture).
- Stamping from a chunk that already has edits copies it as it was before them.

## For Claude: the pipeline

- `python3 tools/efu/world_editor/export_pack.py [OUT_DIR]` applies the saved edits to `res/`, then writes the editor
  (`web/index.html`, `web/editor.js`) with the maps as `pack/` (default `build/world_editor/`). Zip that folder for
  Tom. `web/build.sh` rebuilds `editor.js` from `web/src/` (needs Node; the bundle is committed).
- `python3 tools/efu/apply_world_edits.py` (from `tools/efu`, after `build_raid.py`) applies `world_edits.json`; it is
  idempotent. Each edited chunk becomes its own model (`MAP_MODEL_EFU_EDIT_*`), rebuilt from its base each run, with
  the bases in `world_edit_bases.json`.
- Edits are operations in order (the docstring of `apply_world_edits.py` lists them). An event is found by all of its
  fields, so if `build_raid.py` changes an event that an edit changes too, the edit is skipped with a note: check its
  output.
