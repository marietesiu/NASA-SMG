#!/usr/bin/env bash
# Builds the tileable ground textures for the Moon and Mars landing scenes from the
# whole-planet maps in textures/ (2k_moon.jpg, 2k_mars.jpg).
#
# Why this is needed: those maps are equirectangular planet maps (one pixel = several km).
# Used as-is on a flat 600 m patch of ground they are blurry, they have poles, big dark
# seas and no seams handling. For each body this script:
#   1. crops a calm, evenly cratered region away from the poles,
#   2. upsamples it smoothly (Lanczos) to 2048x2048 and sharpens it slightly,
#   3. makes it seamlessly tileable (cross-fade with a half-tile-shifted copy),
#   4. adds fine film-grain so magnified texels read as surface, not soft blocks,
#   5. scales the brightness to the mean of the procedural ground it replaces, so the
#      lighting that was tuned for that ground still works.
# Requires ImageMagick 7 (`magick`). Run from anywhere: ./tools/make_surface_textures.sh
set -euo pipefail
cd "$(dirname "$0")/.."

SIZE=2048

# make_tile <source> <output> <crop WxH+X+Y> <target mean r g b (0-1, as stored in the png)>
#           <grain 0-1> <flatten 0-1> <flatten blur, px at 256 wide> <contrast multiplier>
make_tile() {
	local src=$1 out=$2 crop=$3 tr=$4 tg=$5 tb=$6 grain=$7 flat=$8 lowsigma=$9 contrast=${10}
	local tmp
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' RETURN

	# 1-2. crop, upsample, sharpen
	magick "$src" -crop "$crop" +repage -colorspace sRGB \
		-filter Lanczos -resize "${SIZE}x${SIZE}!" -unsharp 0x1.4+0.7+0.01 "$tmp/base.png"

	# 3. seamless, one axis at a time. A copy shifted by half a tile has its own seam in the
	# middle and is seamless at the edges; the original is the other way round. Cross-fading
	# with a weight that depends only on x (1 in the middle, 0 at the left and right edges)
	# hides the shifted copy's seam along its whole length, which a weight that depends on
	# both x and y would not. Then the same again for y. (In -fx, u[0] and u[1] are the two
	# images, i and j the pixel position, w and h the image size.)
	magick "$tmp/base.png" \( +clone -roll "+$((SIZE / 2))+0" \) \
		-fx "u[1]+(u[0]-u[1])*sin(pi*(i+0.5)/w)" "$tmp/seamless_x.png"
	magick "$tmp/seamless_x.png" \( +clone -roll "+0+$((SIZE / 2))" \) \
		-fx "u[1]+(u[0]-u[1])*sin(pi*(j+0.5)/h)" "$tmp/seamless.png"

	# 3b. flatten: a tile that repeats every ~120 m shows any broad dark stripe or bright
	# patch as a regular pattern. Divide out `flat` (0-1) of the very low-frequency
	# brightness (a heavily blurred copy, computed small for speed) and keep the fine detail.
	magick "$tmp/seamless.png" -colorspace Gray -resize 256x256 -virtual-pixel Tile -blur "0x$lowsigma" \
		-filter Triangle -resize "${SIZE}x${SIZE}!" -colorspace sRGB "$tmp/low.png"
	local lowmean
	lowmean=$(magick "$tmp/low.png" -format "%[fx:mean]" info:)
	magick "$tmp/seamless.png" "$tmp/low.png" \
		-fx "u[0]*pow($lowmean/max(u[1],0.02),$flat)" "$tmp/flat0.png"
	# 3c. contrast about the mean (the highlands are very even, so they need a push).
	local flatmean
	flatmean=$(magick "$tmp/flat0.png" -format "%[fx:mean]" info:)
	magick "$tmp/flat0.png" -fx "$flatmean+(u-$flatmean)*$contrast" "$tmp/flat.png"

	# 4. grain (per-pixel noise, wrapped blur so it stays tileable)
	magick -size "${SIZE}x${SIZE}" xc:gray50 -attenuate "$grain" +noise Gaussian \
		-colorspace Gray -virtual-pixel Tile -blur 0x0.6 "$tmp/grain.png"
	magick "$tmp/flat.png" "$tmp/grain.png" -compose Overlay -composite "$tmp/grained.png"

	# 5. match the mean colour of the ground this replaces
	local mr mg mb
	read -r mr mg mb <<<"$(magick "$tmp/grained.png" -format "%[fx:mean.r] %[fx:mean.g] %[fx:mean.b]" info:)"
	local fr fg fb
	fr=$(awk -v t="$tr" -v m="$mr" 'BEGIN{printf "%.5f", t/m}')
	fg=$(awk -v t="$tg" -v m="$mg" 'BEGIN{printf "%.5f", t/m}')
	fb=$(awk -v t="$tb" -v m="$mb" 'BEGIN{printf "%.5f", t/m}')
	magick "$tmp/grained.png" \
		-channel R -evaluate multiply "$fr" -channel G -evaluate multiply "$fg" \
		-channel B -evaluate multiply "$fb" +channel \
		-strip -depth 8 -define png:compression-level=9 "$out"

	# Seam check: how much a pixel differs from its wrapped neighbour on the seam
	# versus anywhere else (similar numbers = no visible seam).
	local avg_x seam_x avg_y seam_y
	avg_x=$(magick "$out" \( +clone -roll +1+0 \) -compose Difference -composite -colorspace Gray -format "%[fx:mean]" info:)
	seam_x=$(magick "$out" \( +clone -roll +1+0 \) -compose Difference -composite -colorspace Gray -crop 1x${SIZE}+0+0 +repage -format "%[fx:mean]" info:)
	avg_y=$(magick "$out" \( +clone -roll +0+1 \) -compose Difference -composite -colorspace Gray -format "%[fx:mean]" info:)
	seam_y=$(magick "$out" \( +clone -roll +0+1 \) -compose Difference -composite -colorspace Gray -crop ${SIZE}x1+0+0 +repage -format "%[fx:mean]" info:)
	printf '%s: mean step %.4f / seam step %.4f (x), %.4f / %.4f (y)\n' "$out" "$avg_x" "$seam_x" "$avg_y" "$seam_y"
}

# Moon: evenly cratered western highlands, no dark seas or single dominant crater (a lone
# dark crater would repeat as an obvious grid).
make_tile textures/2k_moon.jpg textures/moon_surface.png 370x370+80+255 0.34 0.34 0.335 0.5 0.6 28 2.2
# Mars: orange plains with darker cratered ground, no polar ice, no large dark seas. Its
# broad dark stripe is flattened out completely so the tile doesn't show up as stripes.
make_tile textures/2k_mars.jpg textures/mars_surface.png 450x450+1500+470 0.60 0.33 0.20 0.5 1.0 18 1.0
