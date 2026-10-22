# Himalayan Duel prototype

Double-click `PLAY_GAME.cmd` to open the game in its own window. You can also open `project.godot` in Godot 4.7 and press **F5**. If the game appears inside the editor, click once inside the game view before using the keyboard. The two health bars at the top confirm that you are in the running game.

Walk the fighters toward each other before attacking. A punch deals 10 damage; a kick deals 16. The first fighter to lose all 100 health loses. Press **R** after a knockout to start again.

| Action | Player 1 | Player 2 |
| --- | --- | --- |
| Move | A / D | Left / Right arrows |
| Jump | W or Space | Up arrow |
| Punch | J | O |
| Kick | K | P |

The two fighters use transparent illustrated sprites in a 3D arena. Their attacks currently use simple distance and direction checks, a hit flash, knockback, and health bars. The sprite motions are prototypes; full fighting animations, blocking, sound, and combos can be added later.

To change damage and attack reach, edit `characters/fighter_controller.gd`. To change the stage or fighter starting positions, edit `scenes/nepal_arena.gd`.
