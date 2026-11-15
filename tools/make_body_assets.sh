#!/usr/bin/env bash
# Builds the game-ready textures for the Earth, Moon and Mars models used by the transit
# scene (transit.tscn) from the raw files in earth/, MoonModel/ and Mars/.
#
# The raw files are far too big to ship as they are: Bump.jpg is 21600x10800 (Godot's
# textures stop at 16384), the night-lights map is 16384x8192, and the Moon relief is a
# 5760x2880 32-bit TIFF, which Godot cannot import at all. Everything is reduced to what a
# planet that fills at most a fifth of the screen can use, and the two relief maps become
# normal maps. Requires ImageMagick 7 (`magick`). Run from anywhere: ./tools/make_body_assets.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# The sources are huge; let ImageMagick spill to disk instead of failing.
export MAGICK_MEMORY_LIMIT=6GiB MAGICK_MAP_LIMIT=6GiB MAGICK_DISK_LIMIT=12GiB

OUT=textures/bodies
mkdir -p "$OUT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# height_to_normal <height image> <output png> <height of 1.0 in km> <radius km> <exaggeration>
# Turns an equirectangular height map into a tangent-space normal map (OpenGL convention,
# green up, as Godot expects). Slopes use the real size of a pixel on the surface, which
# shrinks towards the poles by cos(latitude); `exaggeration` makes the relief readable.
# Done in floating point so gentle slopes do not turn into stair-steps.
height_to_normal() {
	local in=$1 out=$2 km_per_unit=$3 radius=$4 exaggeration=$5
	local w h
	read -r w h <<<"$(magick identify -format '%w %h' "$in")"
	local px_km
	px_km=$(awk -v r="$radius" -v w="$w" 'BEGIN{printf "%.6f", 2*3.14159265358979*r/w}')
	# k = exaggeration / (2 pixels in km), applied to a height difference in km.
	local k
	k=$(awk -v e="$exaggeration" -v p="$px_km" 'BEGIN{printf "%.6f", e/(2*p)}')
	local gx="(p[1,0].r-p[-1,0].r)*$km_per_unit*$k/max(cos(pi*(0.5-(j+0.5)/h)),0.08)"
	local gy="(p[0,1].r-p[0,-1].r)*$km_per_unit*$k"
	local len="sqrt(1+($gx)*($gx)+($gy)*($gy))"
	magick "$in" -virtual-pixel Tile -colorspace Gray -channel R -separate +channel "$TMP/h.miff"
	magick "$TMP/h.miff" -fx "0.5-0.5*($gx)/($len)" "$TMP/nx.miff"
	magick "$TMP/h.miff" -fx "0.5+0.5*($gy)/($len)" "$TMP/ny.miff"
	magick "$TMP/h.miff" -fx "0.5+0.5/($len)" "$TMP/nz.miff"
	magick "$TMP/nx.miff" "$TMP/ny.miff" "$TMP/nz.miff" -combine -colorspace sRGB \
		-strip -depth 8 -define png:compression-level=9 "$out"
}

echo "Earth: colour, land mask, night lights, clouds"
magick earth/earth.jpg -filter Lanczos -resize 4096x2048! -strip -quality 92 "$OUT/earth_day.jpg"
# Land is white in the supplied mask; the shader uses it to make the oceans glossy.
magick earth/Ocean_Mask.png -filter Lanczos -resize 2048x1024! -colorspace Gray -strip -depth 8 "$OUT/earth_land_mask.png"
magick earth/night_lights_modified.png -filter Lanczos -resize 4096x2048! -colorspace Gray -strip -depth 8 "$OUT/earth_night.png"
magick earth/Clouds.png -filter Lanczos -resize 4096x2048! -colorspace Gray -strip -depth 8 "$OUT/earth_clouds.png"

echo "Earth: relief normal map (from Bump.jpg)"
# jpeg:size makes the decoder read the 21600x10800 file at reduced size, which is much faster.
magick -define jpeg:size=5400x2700 earth/Bump.jpg -filter Lanczos -resize 4096x2048! \
	-colorspace Gray -depth 16 "$TMP/earth_height.miff"
# 1.0 in the bump map is taken as ~9 km of relief (Everest is about 8.8 km).
height_to_normal "$TMP/earth_height.miff" "$OUT/earth_normal.png" 9.0 6371.0 12.0

echo "Mars: colour"
magick Mars/DAE/Mars.jpg -filter Lanczos -resize 4096x2048! -strip -quality 92 "$OUT/mars_color.jpg"

echo "Moon: relief normal map (from Moon+Displacement.tif, heights in km)"
magick MoonModel/Moon+Displacement.tif -filter Lanczos -resize 4096x2048! "$TMP/moon_height.miff"
height_to_normal "$TMP/moon_height.miff" "$OUT/moon_normal.png" 1.0 1737.4 5.0

echo "Models: copying the meshes the scene loads"
mkdir -p models
cp MoonModel/Moon.fbx models/Moon.fbx
cp Mars/OBJ/Mars.obj Mars/OBJ/Mars.mtl models/

ls -la "$OUT" models
