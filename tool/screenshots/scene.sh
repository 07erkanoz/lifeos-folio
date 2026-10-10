#!/usr/bin/env bash
# A scene for lifeos.com.tr: a desktop screenshot in a window and a phone
# screenshot in a phone, side by side on a soft background, as the pages of
# the site show Folio. The screenshots come from the tools beside this one
# (invented people and cases only).
#
#   bash tool/screenshots/scene.sh desktop.png phone.png out.png [from] [to]
#
# phone.png may be "-" for a window alone. [from] [to] are the background's
# two colours.
set -euo pipefail
desk=$1
phone=$2
out=$3
from=${4:-#E6EDF9}
to=${5:-#F6F1E8}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

W=2400
H=1500

# The background: a soft diagonal gradient.
magick -size ${W}x${H} xc:"$from" -sparse-color Barycentric "0,0 $from $W,$H $to" "$work/bg.png"

# The window: a title bar over the screenshot, rounded, with a shadow.
inner=1700
[ "$phone" = - ] && inner=2050
magick "$desk" -resize ${inner}x "$work/d.png"
dh=$(magick identify -format %h "$work/d.png")
th=54
wh=$((dh + th))
magick -size ${inner}x${th} xc:'#F1F3F7' \
  -fill '#FF5F57' -draw "circle 28,27 35,27" \
  -fill '#FEBC2E' -draw "circle 52,27 59,27" \
  -fill '#28C840' -draw "circle 76,27 83,27" \
  "$work/bar.png"
magick "$work/bar.png" "$work/d.png" -append "$work/win.png"
magick -size ${inner}x${wh} xc:none -fill white \
  -draw "roundrectangle 0,0,$((inner - 1)),$((wh - 1)),20,20" "$work/mask.png"
magick "$work/win.png" "$work/mask.png" -alpha off -compose CopyOpacity \
  -composite "$work/winr.png"
magick "$work/winr.png" \( +clone -background '#1D2330' -shadow 28x26+0+22 \) \
  +swap -background none -layers merge +repage "$work/wins.png"

if [ "$phone" = - ]; then
  x=$(((W - inner) / 2 - 30))
  magick "$work/bg.png" "$work/wins.png" -geometry +${x}+110 -composite \
    -resize 1600x1000 -quality 90 "$out"
  exit 0
fi

# The phone: its screen in a dark frame, rounded, with a shadow.
pw=430
magick "$phone" -resize ${pw}x "$work/p.png"
ph=$(magick identify -format %h "$work/p.png")
maxh=$((H - 260))
if [ "$ph" -gt "$maxh" ]; then
  magick "$work/p.png" -gravity north -crop ${pw}x${maxh}+0+0 +repage "$work/p.png"
  ph=$maxh
fi
magick -size ${pw}x${ph} xc:none -fill white \
  -draw "roundrectangle 0,0,$((pw - 1)),$((ph - 1)),44,44" "$work/pm.png"
magick "$work/p.png" "$work/pm.png" -alpha off -compose CopyOpacity \
  -composite "$work/pr.png"
fw=$((pw + 36))
fh=$((ph + 36))
magick -size ${fw}x${fh} xc:none -fill '#1D2330' \
  -draw "roundrectangle 0,0,$((fw - 1)),$((fh - 1)),60,60" "$work/frame.png"
magick "$work/frame.png" "$work/pr.png" -geometry +18+18 -composite "$work/ph.png"
magick "$work/ph.png" \( +clone -background '#1D2330' -shadow 32x28+0+24 \) \
  +swap -background none -layers merge +repage "$work/phs.png"

py=$((H - fh - 70))
magick "$work/bg.png" "$work/wins.png" -geometry +70+80 -composite \
  "$work/phs.png" -geometry +$((W - fw - 120))+${py} -composite \
  -resize 1600x1000 -quality 90 "$out"
