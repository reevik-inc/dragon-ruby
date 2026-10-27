## 1010! for DragonRuby Game Toolkit

A port of the Gosu game at https://github.com/shanko/1010 to
[DragonRuby Game Toolkit](https://dragonruby.org). No gems or compiler needed:
the engine binary sits next to this folder.

![Game Board](screenshot.png)

### To play the game

From the `1010` folder:

```sh
./dragonruby                                     # play
./dragonruby mygame --auto                       # the computer plays, game after game
./dragonruby mygame --auto sam                   # choose its strategy: first_fit, last_fit, random_fit, shanko, jc, sam
./dragonruby mygame --auto jc --seed 42          # the same tiles and moves every run
./dragonruby mygame --test tests/board_tests.rb  # run the unit tests
```

Drag one of the 3 tiles on the right onto the board, or pick one (click it, or press
1/2/3) and then click a square. Full rows and columns are cleared, each square
placed scores 1 point, and the game ends when none of the tiles on offer fit.

| Key | Action |
|---|---|
| 1 / 2 / 3 | select a tile |
| O (hold) | show the best spot for the selected tile |
| U | undo the last move |
| N | new game |
| A | auto mode on/off: the computer keeps playing games and tracks runs and best score |
| E | let the computer make one move |
| S / L | save / load (`data/1010game.txt`; it is loaded again at the next start) |
| R | record a new game (press R again to stop) |
| P | play back the last recording |
| C | print where each tile fits first (in the console) |
| Q | save and quit |
| Esc | quit without saving, and delete the saved game so the next start is a new game |
| Right click | drop the selected tile |

When the game closes, the time played (since it opened, over every game) and
the score are printed to the console.

### Where things went

| Original (Gosu) | DragonRuby |
|---|---|
| `board.rb`, `class Board1010` | `app/board.rb`, `class Board` (rules only, no drawing; `Board#play` is one whole move and returns a `Move`) |
| `Board1010::TILES` (number matrices) | `app/tiles.rb`, `class Tile` (shapes drawn as text) |
| `auto_player.rb`, `class AutoPlayer` | `app/auto_player.rb`, `class AutoPlayer` (same strategies) |
| `move_animation.rb`, `class MoveAnimation` (milliseconds) | `app/move_animation.rb`, `class MoveAnimation` (ticks) |
| `game_1010.rb`, `class GameWindow < Gosu::Window` | `app/main.rb`, `class Game` (with `attr_dr` for `state`, `inputs`, `outputs`) |
| `Window#update` + `Window#draw` | `Game#tick`, called 60 times a second through the top-level `tick(args)` |
| `button_down` / `button_up` callbacks | checking `inputs.mouse.key_down.left`, `key_up.left`, `inputs.keyboard.key_down.u`, ... each tick |
| instance variables (`@selected_option`, ...) | `state` (`state.selected_option`, ...) |
| `draw_rect`, `draw_triangle`, `Gosu::Font#draw` | Hashes pushed onto `outputs.sprites` / `outputs.labels` |
| `KEY_ACTIONS` with `Gosu::KB_...` ids | `KEY_ACTIONS` with `key_down` names (`escape:`, `q:`, ...) |
| `Gosu.milliseconds` for the time played | `Kernel.tick_count` (60 ticks = 1 second) |
| `GameWindow#close` prints the time and score | `shutdown`, which DragonRuby calls however the game closes |
| `ruby game_1010.rb auto sam --seed 42` | `./dragonruby mygame --auto sam --seed 42` (read with `GTK.cli_arguments`), or press A while playing |
| `Random.new(seed)`, `sample(random:)` | `Random.new(seed)`, and `list[random.rand(list.length)]` |
| the window caption shows runs and max score | the panel shows them |

### Differences from the original

* Y grows **upwards** in DragonRuby. The board still numbers rows from the top
  like the original, and `cell_xy` in `main.rb` converts rows into screen y.
* Tile colors: the original gave every vertical line value 1 (green); here
  vertical lines are colored by length like horizontal ones.
* Auto mode and playback wait 8 ticks between moves, so you can watch.
* Starting a new game (or loading one) ends a playback in progress.
* A preview shows where the selected tile would land (red if it doesn't fit),
  options that can't fit anywhere are faded, and help is always on screen
  (instead of while H is held). Holding O shows the whole tile, not just its
  anchor square.
* Messages show below the board, and recording shows a blinking square and
  "REC" instead of a triangle.
* L loads the saved game while playing.
* A save file with a score or squares that aren't numbers 0 to 5 is treated as
  damaged instead of crashing the game.
* Not ported: the terminal version (`terminal_game.rb`).

### DragonRuby gotchas found while porting

* `Integer / Integer` returns a Float (`7 / 2 == 3.5`). Use `idiv` or `.floor`.
* `args.state` (set to `{}` in `boot`) is a Hash read with dots. If a key has the
  same name as a method, the method wins: when the game's methods were top-level,
  `state.undo` called the `undo` method, and `rect.size` returns `Hash#size`.
  Keeping the methods inside `class Game` avoids most of these clashes.
* Missing or different from regular Ruby: `Random.new_seed`, `Array#sample(random:)`,
  `Struct.new(..., keyword_init: true)`, `Integer(text, exception: false)` and
  regular expressions. `max_by` can't compare arrays, and
  `each_with_index.to_h { ... }` returns nils instead of raising an error.
* `Kernel.tick_count` can be negative while tests run.
* A method definition without parentheses must not END with a required keyword
  argument. In `def board_squares cells, color, alpha:` DragonRuby read the next
  line as alpha's default value, so the method body silently did nothing.
  Write `def board_squares(cells, color, alpha:)` instead.
