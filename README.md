# Kikimeter
## ToDo
- always show self if not in shown bars (either on top or bottom with placement)
- Maybe use SendAddonMessage for data chunks to improve performance
- use ##SavedVariablesPerCharacter data to store table between sessions
- add scrolling (mousewheel support)
- add button to reset specific sections (the one displayed in the bottom meter)
- query combat status for each player
- add button to list only meter users (for better performance): maybe not a good idea because of boss detection (has to parse every log anyway)

## State
- accuracy of values displayed need further testing
- max players tested so far: 7

## Description
Only works when in a raid or party!  
parses your damage and healing done from the combat log and broadcasts values to other players, eliminating
the issue of inaccuracies caused by players being out of range  
![image](https://github.com/KikidoraFear/Kikimeter/assets/154637862/7a4a5a05-85fa-4402-8ff7-ed47b3b34d5e)
  
Kikimeter supports
- tracking of damage (left), effective heal (middle), over heal (right)
- 2 separate meters that can track different sections of the fight
- ranking and sorting of players
- damage values from pets are added to their owners
- detailed break down of spells and hits on hover (pet's damage indicated with Pet: ...)
- detailed spells are sorted by value
