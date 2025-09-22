osascript <<EOF
-- Open a new Safari window
tell application "Safari"
    make new document
    set DUMMY_SAFARI_WINDOW to id of front window
    tell window id DUMMY_SAFARI_WINDOW
        set visible to false
    end tell
end tell

-- Get desktop dimensions
tell application "Finder"
    set desktopBounds to bounds of window of desktop
    set desktopWidth to item 3 of desktopBounds
    set desktopHeight to item 4 of desktopBounds
end tell

set inspectorWidth to desktopWidth / 3
log "Desktop: " & desktopWidth & "x" & desktopHeight & ", Inspector width: " & inspectorWidth

-- Function to find Safari windows across all processes
on findSafariWindows()
    set safariWindows to {}
    tell application "System Events"
        tell process "Safari"
            repeat with win in windows
                try
                    set winTitle to title of win
                    set end of safariWindows to {win, winTitle}
                on error
                    -- Skip windows we can't access
                end try
            end repeat
        end tell
    end tell
    return safariWindows
end findSafariWindows

tell application "System Events"
    tell process "Safari"
        tell menu "Develop" of menu bar 1
            repeat with i from 1 to count of menu items
                set currentMenuItem to menu item i
                set fullItemName to name of currentMenuItem
                
                if fullItemName contains "(Simulator)" then
                    -- Parse device info
                    set oldDelimiters to AppleScript's text item delimiters
                    set AppleScript's text item delimiters to {return, linefeed}
                    set deviceName to text 1 thru -13 of (item 1 of (text items of fullItemName))
                    set AppleScript's text item delimiters to oldDelimiters
                    
                    log "========================================="
                    log "Processing: " & deviceName
                    log "========================================="
                    
                    -- Get existing Safari windows before
                    set windowsBefore to my findSafariWindows()
                    log "BEFORE - Safari windows:"
                    repeat with winInfo in windowsBefore
                        log "  - " & (item 2 of winInfo)
                    end repeat
                    
                    click currentMenuItem
                    delay 1
                    
                    try
                        repeat with subItem in menu items of menu 1 of currentMenuItem
                            if (name of subItem) contains "localhost" then
                                click subItem
                                delay 2
                                exit repeat
                            end if
                        end repeat
                        
                        -- Get Safari windows after
                        set windowsAfter to my findSafariWindows()
                        log "AFTER - Safari windows:"
                        repeat with winInfo in windowsAfter
                            log "  - " & (item 2 of winInfo)
                        end repeat
                        
                        -- Find the new Web Inspector window
                        set newInspectorWindow to missing value
                        repeat with afterWinInfo in windowsAfter
                            set afterWin to item 1 of afterWinInfo
                            set afterTitle to item 2 of afterWinInfo
                            
                            -- Check if this window existed before
                            set wasExisting to false
                            repeat with beforeWinInfo in windowsBefore
                                if (item 2 of beforeWinInfo) is afterTitle then
                                    set wasExisting to true
                                    exit repeat
                                end if
                            end repeat
                            
                            -- If it's new and contains Web Inspector and device name
                            if not wasExisting and afterTitle contains "Web Inspector" and afterTitle contains deviceName then
                                set newInspectorWindow to afterWin
                                log "Found NEW Web Inspector: " & afterTitle
                                exit repeat
                            end if
                        end repeat
                        
                        if newInspectorWindow is not missing value then
                            -- Find matching simulator position
                           tell application "System Events"
                              tell process "Simulator"
                                  repeat with simWin in windows
                                      try
                                          set simWinName to title of simWin
                                          
                                            -- Extract device name from simulator window title
                                            set oldDelimiters to AppleScript's text item delimiters
                                            set AppleScript's text item delimiters to " –"
                                            set simTitleParts to text items of simWinName
                                            set AppleScript's text item delimiters to oldDelimiters

                                            if (count of simTitleParts) >= 1 then
                                                set simDeviceName to item 1 of simTitleParts
                                                log "Comparing simulator device: '" & simDeviceName & "' with menu device: '" & deviceName & "'"
                                                
                                                if simDeviceName is deviceName then
                                                    log "Found matching simulator: " & simWinName
                                                    
                                                    set simPos to position of simWin
                                                    set simX to item 1 of simPos
                                                    
                                                    log "Positioning Web Inspector at X: " & simX
                                                    
                                                    -- Position the Web Inspector window
                                                    tell newInspectorWindow
                                                        set position to {simX, 0}
                                                        set size to {inspectorWidth, desktopHeight}
                                                    end tell
                                                    
                                                    log "Successfully positioned " & deviceName & " Web Inspector"
                                                    exit repeat
                                                end if
                                            end if
                                      on error
                                          -- Skip simulator windows we can't access
                                      end try
                                  end repeat
                              end tell
                          end tell
                        else
                            log "Could not find new Web Inspector for: " & deviceName
                        end if
                        
                    on error errMsg
                        log "Error: " & errMsg
                    end try
                    
                    log "" -- Empty line for readability
                end if
            end repeat
        end tell
    end tell
end tell

-- Send all Web Inspectors to back
tell application "Simulator" to activate
tell application "Terminal" to activate

tell application "Safari"
    try
        tell window id DUMMY_SAFARI_WINDOW
            close
        end tell
        log "Closed original Safari window"
    on error
        log "Could not close original Safari window (may already be closed)"
    end try
end tell

log "Complete!"
EOF