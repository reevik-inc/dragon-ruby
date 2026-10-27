# DragonRuby games

Small games written with [DragonRuby Game Toolkit](https://dragonruby.org).

| Game | What it is |
|---|---|
| [1010](1010/mygame/README.md) | A port of the Gosu game [1010](https://github.com/shanko/1010): place tiles, clear full rows and columns. The computer can play it too, with several strategies. |
| [tic-tac-toe](tic-tac-toe/mygame) | Tic-tac-toe for one or two players, written to learn DragonRuby. |

Only each game's own code is in this repository (its `mygame/app`, `mygame/tests`
and docs), not the DragonRuby SDK, which you get from https://dragonruby.org.

## Running a game

1. Unzip the DragonRuby SDK and copy it to a folder named after the game, e.g. `1010/`.
2. Put this repository's `1010/mygame/` files over the SDK's `mygame/` folder.
3. From that folder, run `./dragonruby` to play, or
   `./dragonruby mygame --test tests/<name>_tests.rb` to run the tests.

Built and tested with DragonRuby 7.25 on macOS.

## License

MIT: see [LICENSE](LICENSE). The DragonRuby SDK has its own license and is not part of this repository.
