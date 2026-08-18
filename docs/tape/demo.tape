# Hero recording for the README: a whole run, top to bottom.
#
# It runs `geocheck --demo`, which renders invented measurements from
# documentation address space. That is deliberate — a recording of a real run
# would publish the recorder's address, network and every hop between them.
#
# Regenerate with: make demo

Output docs/img/demo.gif

Set Shell "bash"
Set FontSize 14
Set Width 1280
Set Height 1810
Set Padding 24
Set Margin 24
Set MarginFill "#181825"
Set BorderRadius 12
Set WindowBar Colorful
Set Theme "Catppuccin Mocha"
Set TypingSpeed 15ms

Hide
Type "export PATH=/vhs/.vhs-bin:$PATH"
Enter
# geocheck picks its palette from COLORFGBG; the recording is on a dark theme.
Type "export COLORFGBG='15;0' CLICOLOR_FORCE=1"
Enter
Type "export PS1='$ '"
Enter
Type "clear"
Enter
Show

Sleep 900ms
Type "geocheck --demo --no-ai --no-mtr"
Sleep 600ms
Enter
Sleep 6s
