#!/system/bin/sh
# Guest-side, as root. Mantis assumes a phone (rotation 0 = portrait) and sizes its overlay and touch space from
# that, so present the landscape display as a portrait-natural one turned 90 degrees. The rotation lock also keeps
# Mantis's portrait activity from rotating the display, which costs Unity games their surface.
physical=$(wm size | sed -n 's/^Physical size: //p')
width=${physical%x*}
height=${physical#*x}
if [ "$width" -gt "$height" ]; then
    wm size "${height}x${width}"
    wm fixed-to-user-rotation enabled
    wm user-rotation lock 1
fi
