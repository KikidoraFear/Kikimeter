# KikiMeter
## ToDo
- add buttons on top to reset/pause every table with one click
- always show self if not in shown bars (either on top or bottom with placement)
- Use SendAddonMessage for data chunks to imrpove performance
- use ##SavedVariablesPerCharacter data to store table between sessions


## State
- accuracy of values displayed need further testing
- max players tested so far: 2

## Description
Only works when in a raid or party!  
parses your damage and healing done from the combat log and broadcasts values to other players, eliminating
the issue of inaccuracies caused by players being out of range  
![Screenshot 2023-12-27 194439](https://github.com/KikidoraFear/Kikimeter/assets/154637862/e27c3e2f-a9a4-4963-92a4-b56bdc2f7f17)
  
KikiMeter supports
- tracking of damage (left), effective heal (middle), over heal (right)
- 3 separate meters that can be paused and reset individually (top, middle, bottom)
- ranking and sorting of players
- mousewheel scroll
- damage values from pets are added to their owners
- detailed break down of spells and hits on hover (pet's damage indicated with Pet: ...)
- detailed spells are sorted by value
- Hide button (top right) to hide window (click button again to show)
