on run argv
    set volName to item 1 of argv
    set appName to volName & ".app"

    tell application "Finder"
        tell disk volName
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set bounds of container window to {200, 200, 660, 440}
            set viewOptions to the icon view options of container window
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 80
            set position of item appName of container window to {120, 120}
            set position of item "Applications" of container window to {340, 120}
            close
            open
            update without registering applications
            delay 1
            close
        end tell
    end tell
end run
