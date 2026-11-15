Low Poly Launch Complex Free
============================

16 low-poly props for a rocket test site's fuel farm whose machines work, taken from Low Poly
Launch Complex (97 props, 23 working machines, a test site at dusk whose rocket flies):
https://heyheythere.itch.io/low-poly-launch-complex
Built on Low Poly Industrial Facility's grid and look, so the two combine:
https://heyheythere.itch.io/low-poly-industrial-facility
One 2048x2048 texture atlas filtered with mipmaps, the occlusion baked into vertex colours,
real-world scale (1 unit = 1 metre).

What's in the zip
-----------------
glb/        one file per prop, with its animations (the best format for Godot, Blender, three.js)
fbx/        one file per prop, with its animations as takes (Unreal, Unity, most 3D apps)
obj/        one file per prop, still (any 3D app)
textures/   atlas.png, the one texture every prop uses, its glow map, and the seamless ground and
            concrete textures it tiles from, 128x128 a metre, for your own geometry
icons/      an icon per prop, 256x256 PNG with transparency
props.json  every prop: title, group, size, triangles, parts, animations and its "use" (what kind
            of machine it is and how it's set up)
blender/    every prop in one .blend, the atlas packed in
addons/     the Godot addon, low_poly_launch_complex/: this folder is a Godot 4.3+ project that
            opens on its gallery (.gdignore keeps Godot out of the other folders)

The machines
------------
A prop that works has machine.gd on it, set up as its "use" in props.json says: the fuel valve
turns open in two quarter turns, the pressure gauge reads the valve it needs, the transfer pumps
are a switch whose motors run while it's on, and the lamp post and the pad's beacon light (the
beacon turning) while what they need is live; with nothing to need they're on. A machine is
powered while every machine it needs is live, and live while it's on and powered; it refuses a
use without power.

The grid
--------
The ground and the concrete are 4 m squares, their pivots at their centres, on Low Poly
Industrial Facility's 2 m grid. The bund wall and the fence are 4 m long, centred on a square's
edge, their fronts facing -Y in Blender (+Z in Godot): turn them 90 degrees for the other edges.

Godot 4.3 and later
-------------------
Copy addons/low_poly_launch_complex/ into your project's addons/ folder. Each prop is a scene in
props/: drag it into your level and turn on grid snapping at 1 m. It has a box collider
(StaticBody3D) on each of its parts, the moving parts' colliders moving with them, and a prop with
animations has an AnimationPlayer. Wire what a machine needs in the inspector (needs), or in code,
and listen for its signals:

    pumps.needs = [pumps.get_path_to(valve)]   # valve, pumps: in your level
    valve.use()                                # what the player's use key calls

demo/gallery.tscn shows every prop: drag to turn, arrows to browse, A for all of them.
Low Poly Launch Complex uses the same addon folder: it installs over this one.
The props use one material, props.tres: the atlas times the vertex colours, lit, with the glow map.

Other engines and apps
----------------------
Use fbx/, glb/ or obj/ with textures/atlas.png, filtered, with mipmaps, multiplied by the vertex
colours (the baked occlusion) in your material. The machines are Godot's script; elsewhere their
animations are there to play, and props.json says how each is meant to work.

The site is made up: no real agency's, maker's or range's name, number or emblem is shown.

License: CC BY 4.0, see LICENSE.txt for the credit line. Made by heyheythere:
https://heyheythere.itch.io
