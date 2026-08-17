# The part of the report no other tool prints: how directly each network is
# reached. Short enough to fit on screen in full, so the closing frame is the
# whole analysis rather than its tail.
#
# Regenerate with: make demo

Output docs/img/connectivity.gif

Set Shell "bash"
Set FontSize 14
Set Width 1180
Set Height 830
Set Padding 24
Set Margin 24
Set MarginFill "#181825"
Set BorderRadius 12
Set WindowBar Colorful
Set Theme "Catppuccin Mocha"
Set TypingSpeed 55ms

Hide
Type "export PATH=/vhs/.vhs-bin:$PATH"
Enter
Type "export COLORFGBG='15;0' CLICOLOR_FORCE=1"
Enter
Type "export PS1='$ '"
Enter
Type "clear"
Enter
Show

Sleep 900ms
Type "geocheck --demo --no-geo --no-portal --no-access --no-reputation"
Sleep 600ms
Enter
Sleep 6s
