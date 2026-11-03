# dmgbuild settings for Scrub's installer. Paths are passed with -D:
#   dmgbuild -s scripts/dmg-settings.py -D app=path/to/Scrub.app -D background=path/to/background.tiff \
#            -D icon=path/to/AppIcon.icns "Scrub" dist/Scrub.dmg
import os

app = defines["app"]
app_name = os.path.basename(app)

format = "UDZO"
filesystem = "APFS"
compression_level = 9
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines.get("icon")
background = defines["background"]

window_rect = ((200, 160), (640, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
icon_size = 112
text_size = 13
arrange_by = None
label_pos = "bottom"
icon_locations = {
    app_name: (170, 205),
    "Applications": (470, 205),
}
hide_extension = [app_name]
