# OpenRocket + GMAT -> Godot 4 Integration

## Reference Paths
- **OpenRocket Spec:** `docs/openrocket_godot_specification.md`
- **OpenRocket Source:** `/home/mario/OpenRocket/core/src/main/java/info/openrocket/core/`
- **GMAT Installation:** `/home/mario/GMAT/` (`bin/GmatConsole`, `samples/`, `docs/`)

## Simulation Handoff Architecture
1. **Atmospheric Phase (OpenRocket):** Simulates launch rail to upper-atmosphere staging / MECO (`+X` nose, `+Y` up, `+Z` right).
2. **Orbital Phase (GMAT):** Receives final ascent state vector (`X, Y, Z, VX, VY, VZ`, epoch, dry mass) in `EarthMJ2000Eq` (`+Z` North Pole, `+X` Vernal Equinox). Run headlessly by generating a `.script` file and executing `LD_LIBRARY_PATH=/home/mario/GMAT/bin /home/mario/GMAT/bin/GmatConsole <mission.script>` (use `GmatConsole` CLI + `ReportFile`/`EphemerisFile` outputs rather than `gmatpy`, as Arch Linux uses a newer system Python than 3.12).
3. **Godot 4 Visualization:** Maps simulator frames into Godot's right-handed Y-up frame (`-Z` forward, `+Y` up, `+X` right) and scales orbital kilometers to prevent float32 jitter.
