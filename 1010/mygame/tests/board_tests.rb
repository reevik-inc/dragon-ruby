# Unit tests for app/tiles.rb, app/board.rb, app/auto_player.rb,
# app/move_animation.rb, app/leaderboard.rb, app/game_log.rb and the Game
# class in app/main.rb.
# Run from the 1010 folder:
#   ./dragonruby mygame --test tests/board_tests.rb
#
# Every method named test_* is run with a fresh `args` and an `assert` object.

def tile name
  TILES_BY_NAME[name]
end

# Fills a whole row except the listed columns.
def fill_row board, row, except: []
  Board::COLS.times { |c| board.cells[row][c] = 1 unless except.include?(c) }
end

# A Game wired to the test's args, with a fresh board (not a saved game).
# Its high scores stay in memory unless `options` names a scores_file.
def new_test_game args, seed: 1, strategy: :jc, game_class: Game, **options
  args.state = {}
  game = game_class.new
  game.args = args
  game.setup({ auto: false, strategy: strategy, seed: seed, scores_file: nil }.merge(options))
  game.new_game
  game
end

# A file name DragonRuby refuses to write, as if the disk were full.
UNWRITABLE_FILE = "data/\0unwritable.txt"

# Fills the board so that only `tile` fits, and only at (0, 0).
def leave_one_spot board, tile
  Board::ROWS.times { |r| fill_row board, r }
  board.cells_for(tile, 0, 0).each { |r, c| board.cells[r][c] = Board::EMPTY }
  board.options.replace [tile]
end

# Holes on every third diagonal: every row and column has holes (so no line
# is full, even after filling one), and no 3x3 space is left anywhere. So
# placing the dot at (0, 0) ends the game: only sq3s are left.
def one_move_from_game_over board
  Board::ROWS.times do |r|
    Board::COLS.times { |c| board.cells[r][c] = (r + c) % 3 == 0 ? Board::EMPTY : 1 }
  end
  board.options.replace [tile(:dot), tile(:sq3), tile(:sq3)]
end

# A Game whose Esc and R only note that they were called (the real Esc
# would quit the test run).
class KeyTestGame < Game
  attr_reader :called

  [:quit_without_saving, :toggle_recording].each do |action|
    define_method(action) { (@called ||= []) << action }
  end
end

# Plays a whole game with the computer, straight on the board.
def play_whole_game player, board
  board.deal_if_needed
  moves = 0
  until board.game_over? || moves > 1000
    board.play(*player.choose_move(board))
    moves += 1
  end
  board
end

# Runs the save file tests without losing a game the player saved.
def keeping_the_save_file
  saved = DR.read_file SAVE_FILE
  yield
ensure
  if saved
    DR.write_file SAVE_FILE, saved
  elsif DR.stat_file(SAVE_FILE)
    DR.delete_file SAVE_FILE
  end
end

# --- Tiles ------------------------------------------------------------------

def test_there_are_19_tiles args, assert
  assert.equal! ALL_TILES.length, 19
  assert.equal! SMALL_TILES.compact.length, 8
end

def test_tile_shapes_and_anchors args, assert
  assert.equal! tile(:hl3).cells, [[0, 0], [0, 1], [0, 2]]
  assert.equal! tile(:vl2).cells, [[0, 0], [1, 0]]
  assert.equal! tile(:sq3).cells.length, 9
  assert.equal! tile(:tl3).anchor, 0
  assert.equal! tile(:br2).anchor, 1   # ".#": the first filled square is column 1
  assert.equal! tile(:br3).anchor, 2
end

# --- Placing ----------------------------------------------------------------

def test_place_scores_one_point_per_square args, assert
  board = Board.new
  assert.equal! board.place(tile(:sq2), 0, 0), 4
  assert.equal! board.score, 4
  assert.equal! board.cells[1][1], 2
end

def test_cannot_place_on_top_of_other_tiles_or_off_the_board args, assert
  board = Board.new
  board.place tile(:dot), 5, 5
  assert.equal! board.place(tile(:hl3), 5, 4), 0  # would cover (5, 5)
  assert.equal! board.place(tile(:hl3), 0, 8), 0  # runs off the right edge
  assert.equal! board.place(tile(:vl5), 7, 0), 0  # runs off the bottom
  assert.false! board.fits?(tile(:br2), 0, 0)     # its anchor shifts it off the left edge
  assert.true!  board.fits?(tile(:hl3), 5, 6)
  assert.equal! board.score, 1
end

def test_anchor_shifts_the_tile_left args, assert
  # br2 is ".#" over "##", so dropping it on (0, 5) covers (0,5), (1,4), (1,5).
  board = Board.new
  board.place tile(:br2), 0, 5
  assert.equal! board.cells_for(tile(:br2), 0, 5), [[0, 5], [1, 4], [1, 5]]
  assert.equal! board.cells[1][4], 2
end

# --- A whole move (Board#play) ----------------------------------------------------

def test_play_scores_and_uses_up_the_option args, assert
  board = Board.new options: [tile(:sq2), tile(:dot)]
  move  = board.play 0, 0, 0

  assert.equal! board.score, 4
  assert.equal! board.options, [tile(:dot)]
  assert.equal! move.placed, [[0, 0, 2], [0, 1, 2], [1, 0, 2], [1, 1, 2]]
  assert.equal! move.cleared_rows, []
  assert.equal! move.cleared_cols, []
end

def test_play_returns_nil_and_changes_nothing_when_the_tile_does_not_fit args, assert
  board = Board.new options: [tile(:hl3)]
  assert.equal! board.play(0, 0, 8), nil  # off the right edge
  assert.equal! board.play(5, 0, 0), nil  # no such option
  assert.equal! board.options, [tile(:hl3)]
  assert.equal! board.score, 0
end

# --- Clearing lines -----------------------------------------------------------

def test_full_row_is_cleared args, assert
  board = Board.new options: [tile(:dot), tile(:dot)]
  fill_row board, 3, except: [9]
  move = board.play 0, 3, 9

  assert.equal! move.cleared_rows, [3]
  assert.equal! move.cleared_cols, []
  assert.true! board.cells[3].all? { |v| v == Board::EMPTY }
  assert.equal! move.cells_before_clearing[3][9], 1  # the move remembers the row before it was cleared
end

def test_row_and_column_cleared_together args, assert
  board = Board.new options: [tile(:dot), tile(:dot)]
  fill_row board, 0, except: [0]
  (1...Board::ROWS).each { |r| board.cells[r][0] = 1 }
  move = board.play 0, 0, 0

  assert.equal! [move.cleared_rows, move.cleared_cols], [[0], [0]]
  assert.equal! board.cells.flatten.uniq, [Board::EMPTY]
end

def test_play_deals_three_new_tiles_once_all_are_used args, assert
  board = Board.new options: [tile(:dot)]
  fill_row board, 0, except: [9]

  move = board.play 0, 0, 9
  assert.equal! move.cleared_rows, [0]      # the dot completed row 0
  assert.equal! board.score, 1
  assert.equal! board.options.length, 3     # the last option was used, so 3 new ones
end

# --- Options and game over ------------------------------------------------------

def test_deals_three_tiles_only_when_empty args, assert
  board = Board.new
  board.deal_if_needed
  assert.equal! board.options.length, 3

  board.options.delete_at 0
  board.deal_if_needed
  assert.equal! board.options.length, 2
end

def test_the_same_seed_deals_the_same_tiles args, assert
  deals = lambda do |seed|
    board = Board.new(random: Random.new(seed))
    10.times.map { board.generate_options.map(&:name) }
  end
  assert.equal! deals.call(42), deals.call(42)
  # Another seed could deal the same 3 by chance, but not 10 deals in a row.
  assert.true! deals.call(42) != deals.call(43)
end

def test_game_over_when_nothing_fits args, assert
  board = Board.new
  Board::ROWS.times { |r| fill_row board, r }
  board.cells[0][0] = Board::EMPTY        # only one free square
  board.options.replace [tile(:hl2), tile(:sq2)]
  assert.true! board.game_over?

  board.options << tile(:dot)
  assert.false! board.game_over?
end

def test_generate_options_swaps_in_a_small_tile_that_fits args, assert
  board = Board.new
  Board::ROWS.times { |r| fill_row board, r }
  board.cells[0][0] = Board::EMPTY
  board.cells[0][1] = Board::EMPTY        # room for hl2 only (or a dot)

  20.times do
    options = board.generate_options
    assert.true! options.any? { |t| board.fits_anywhere?(t) }
  end
end

# --- Positions and measures -------------------------------------------------------

def test_find_position_and_positions_for args, assert
  board = Board.new
  assert.equal! board.find_position(tile(:sq3)), [0, 0]
  assert.equal! board.positions_for(tile(:sq3)).length, 64  # 8 x 8 places for a 3x3 square

  board.cells.each { |row| row.fill(1) }
  assert.equal! board.find_position(tile(:dot)), nil
  assert.false! board.fits_anywhere?(tile(:dot))
end

def test_neighbours_and_edges args, assert
  board = Board.new
  board.cells[4][4] = board.cells[4][5] = board.cells[5][4] = 1

  assert.equal! board.filled_neighbours(5, 5), 3
  assert.equal! board.filled_neighbours(0, 0), 0
  assert.equal! board.edges_touched(0, 0), 2
  assert.equal! board.edges_touched(0, 5), 1
  assert.equal! board.edges_touched(9, 9), 2
  assert.equal! board.edges_touched(5, 5), 0
end

def test_lines_completed_by_does_not_change_the_board args, assert
  board = Board.new
  fill_row board, 2, except: [8, 9]

  assert.equal! board.lines_completed_by(tile(:hl2), 2, 8), 1
  assert.equal! board.lines_completed_by(tile(:hl2), 3, 8), 0
  assert.equal! board.cells[2][8], Board::EMPTY
  assert.equal! board.score, 0
end

# --- Computer player (auto_player.rb) -------------------------------------------

def test_jc_prefers_a_corner_on_an_empty_board args, assert
  assert.equal! AutoPlayer.new(:jc).best_position(Board.new, tile(:dot)), [0, 0]
end

def test_jc_prefers_a_crowded_spot args, assert
  board = Board.new
  # Surround (5, 5) on three sides so it beats the corners.
  [[4, 4], [4, 5], [4, 6], [5, 4], [5, 6]].each { |r, c| board.cells[r][c] = 1 }
  assert.equal! AutoPlayer.new(:jc).best_position(board, tile(:dot)), [5, 5]
end

def test_shanko_ignores_the_edges args, assert
  board = Board.new
  [[4, 4], [4, 5]].each { |r, c| board.cells[r][c] = 1 }
  # Next to the two filled squares beats a corner for shanko, but jc counts
  # the corner's 2 edges, which ties, and the corner comes first.
  assert.equal! AutoPlayer.new(:shanko).best_position(board, tile(:dot)), [3, 4]
  assert.equal! AutoPlayer.new(:jc).best_position(board, tile(:dot)), [0, 0]
end

def test_first_fit_and_last_fit args, assert
  board = Board.new
  assert.equal! AutoPlayer.new(:first_fit).best_position(board, tile(:sq2)), [0, 0]
  assert.equal! AutoPlayer.new(:last_fit).best_position(board, tile(:sq2)), [8, 8]
end

def test_random_fit_picks_a_position_that_fits args, assert
  board  = Board.new
  player = AutoPlayer.new(:random_fit, random: Random.new(3))
  10.times do
    row, col = player.best_position(board, tile(:sq3))
    assert.true! board.fits?(tile(:sq3), row, col)
  end
end

def test_sam_completes_a_line_when_it_can args, assert
  board = Board.new
  Board::COLS.times { |c| board.cells[9][c] = 1 unless c == 3 }
  assert.equal! AutoPlayer.new(:sam).best_position(board, tile(:dot)), [9, 3]
end

def test_sam_falls_back_to_jc_when_no_line_completes args, assert
  board = Board.new
  [[4, 4], [4, 5], [4, 6], [5, 4], [5, 6]].each { |r, c| board.cells[r][c] = 1 }
  assert.equal! AutoPlayer.new(:sam).best_position(board, tile(:dot)), [5, 5]
end

def test_no_position_when_the_tile_fits_nowhere args, assert
  board = Board.new
  board.cells.each { |row| row.fill(1) }
  assert.equal! AutoPlayer.new.best_position(board, tile(:dot)), nil
  board.options.replace [tile(:dot)]
  assert.equal! AutoPlayer.new.choose_move(board), nil
end

def test_unknown_strategy_is_rejected_with_the_choices args, assert
  message = nil
  begin
    AutoPlayer.new(:best)
  rescue ArgumentError => e
    message = e.message
  end
  assert.true! message.include?("jc"), message
end

def test_choose_move_only_picks_a_tile_that_fits args, assert
  board = Board.new options: [tile(:sq3), tile(:dot)]
  Board::ROWS.times { |r| fill_row board, r }
  board.cells[0][0] = Board::EMPTY

  10.times { assert.equal! AutoPlayer.new.choose_move(board), [1, 0, 0] }
end

def test_every_strategy_plays_whole_games args, assert
  AutoPlayer::STRATEGIES.each do |strategy|
    player = AutoPlayer.new(strategy, random: Random.new(1))
    board  = play_whole_game player, Board.new(random: Random.new(1))
    assert.true! board.game_over?, strategy
    assert.true! board.score > 0, strategy
  end
end

def test_the_same_seeds_repeat_the_same_game args, assert
  scores = 2.times.map do
    player = AutoPlayer.new(:jc, random: Random.new(7))
    play_whole_game(player, Board.new(random: Random.new(7))).score
  end
  assert.equal! scores[0], scores[1]
end

# --- Move animation (move_animation.rb) --------------------------------------------

# An hl2 that completes row 0 at (0, 8) and (0, 9), played at tick 1000.
def animated_move
  board = Board.new options: [tile(:hl2), tile(:dot)]
  Board::COLS.times { |c| board.cells[0][c] = 1 unless c >= 8 }
  move = board.play 0, 0, 8
  [board, MoveAnimation.new(move, 1000)]
end

def test_animation_shows_the_placed_squares_one_per_step args, assert
  board, animation = animated_move
  step = MoveAnimation::PLACE_STEP_TICKS
  assert.equal! animation.value_at(0, 8, board.cells[0][8], 1000), 2           # the first square shows at once
  assert.equal! animation.value_at(0, 9, board.cells[0][9], 1000), Board::EMPTY # the second isn't there yet
  assert.equal! animation.value_at(0, 9, board.cells[0][9], 1000 + step), 2
end

def test_animation_shows_a_cleared_row_until_it_empties args, assert
  board, animation = animated_move
  cleared_at = 1000 + 2 * MoveAnimation::PLACE_STEP_TICKS
  assert.equal! animation.value_at(0, 0, board.cells[0][0], cleared_at - 1), 1
  assert.equal! animation.value_at(0, 0, board.cells[0][0], cleared_at), Board::EMPTY
  assert.equal! animation.value_at(5, 5, board.cells[5][5], 1000), Board::EMPTY  # away from the move
end

def test_animation_is_done_after_the_last_line_empties args, assert
  _board, animation = animated_move
  ends_at = 1000 + 2 * MoveAnimation::PLACE_STEP_TICKS + MoveAnimation::CLEAR_STEP_TICKS
  assert.false! animation.done?(ends_at - 1)
  assert.true! animation.done?(ends_at)
end

def test_animation_empties_one_row_and_one_column_per_step args, assert
  # Rows 1 and 2 and column 0 are full but for (1, 0) and (2, 0), so a vl2
  # there clears 2 rows and 1 column.
  board = Board.new options: [tile(:vl2), tile(:dot)]
  fill_row board, 1, except: [0]
  fill_row board, 2, except: [0]
  Board::ROWS.times { |r| board.cells[r][0] = 1 unless r == 1 || r == 2 }
  move = board.play 0, 1, 0
  assert.equal! [move.cleared_rows, move.cleared_cols], [[1, 2], [0]]

  # 2 squares placed at ticks 0 and 1, then clearing starts at tick 2:
  # row 1 and column 0 first, row 2 one step (10 ticks) later.
  animation = MoveAnimation.new move, 0, clear_step: 10
  value = ->(row, col, now) { animation.value_at(row, col, board.cells[row][col], now) }
  assert.equal! value.call(1, 5, 1), 1
  assert.equal! value.call(1, 5, 2), Board::EMPTY
  assert.equal! value.call(5, 0, 2), Board::EMPTY
  assert.equal! value.call(2, 5, 11), 1
  assert.equal! value.call(2, 5, 12), Board::EMPTY
  assert.false! animation.done?(21)
  assert.true! animation.done?(22)
end

# --- Copying and saving -----------------------------------------------------------

def test_copy_is_independent args, assert
  board = Board.new options: [tile(:dot)]
  copy  = board.copy
  board.play 0, 0, 0

  assert.equal! copy.cells[0][0], Board::EMPTY
  assert.equal! copy.options, [tile(:dot)]
  assert.equal! copy.score, 0
  assert.true! copy.random.equal?(board.random)  # so playback deals the same tiles after an undo
end

def test_save_and_load_round_trip args, assert
  board = Board.new options: [tile(:hl5), tile(:dot)]
  board.play 1, 2, 3

  copy = Board.from_save board.to_save
  assert.equal! copy.score, board.score
  assert.equal! copy.cells, board.cells
  assert.equal! copy.options.map(&:name), [:hl5]
end

# Why Board.from_save rejects `text`, or nil if it doesn't.
def save_problem text
  Board.from_save text
  nil
rescue Board::DamagedSave => e
  e.message
end

def test_damaged_save_is_rejected_with_the_reason args, assert
  good = Board.new(options: [tile(:dot)]).to_save
  assert.equal! save_problem(good), nil
  assert.equal! save_problem(good + "\n\n"), nil  # blank lines are fine
  assert.equal! save_problem("score=10\nrow=000"), 'row 1 is "000", not 10 of the digits 012345'
  assert.equal! save_problem("not a saved game"), 'line 1 is not understood: "not a saved game"'
  assert.equal! save_problem(good.sub("score=0", "score=lots")), 'the score "lots" is not a whole number'
  assert.equal! save_problem(good.sub("score=0", "score")), 'the score "" is not a whole number'
  assert.equal! save_problem(good.sub("score=0\n", "")), "the score is missing"
  assert.equal! save_problem(good.sub("options=dot", "options=dot,blob")), 'there is no tile named "blob"'
  assert.equal! save_problem(good.sub("options=dot", "options=dot,dot,dot,dot")), "it offers 4 tiles, more than 3"
  assert.equal! save_problem(good.sub("row=0000000000\n", "")), "it has 9 rows instead of 10"
  assert.equal! save_problem(good.sub("row=0000000000", "row=0000090000")),  # no tile has value 9
                'row 1 is "0000090000", not 10 of the digits 012345'
end

# --- Game (main.rb) -------------------------------------------------------------

def test_command_line_options args, assert
  assert.equal! Game.options_from({}), { auto: false, strategy: :jc }
  assert.equal! Game.options_from({ auto: nil }), { auto: true, strategy: :jc }
  assert.equal! Game.options_from({ auto: "sam", seed: "42" }), { auto: true, strategy: "sam", seed: 42 }
end

def test_a_bad_seed_is_reported_and_a_random_one_used args, assert
  options = Game.options_from({ seed: "abc" })
  assert.equal! options[:seed], nil
  assert.equal! options[:warnings], ['--seed needs a whole number, not "abc": using a random seed']
  assert.equal! Game.options_from({ seed: nil })[:warnings].length, 1  # a bare --seed

  args.state = {}
  game = Game.new
  game.args = args
  game.setup options
  assert.equal! args.state.message.level, :warn
  assert.true! args.state.session_seed.is_a?(Integer)
end

def test_an_unknown_strategy_falls_back_to_jc args, assert
  game = new_test_game args, strategy: "best"
  assert.equal! args.state.auto_player.strategy, :jc
  assert.equal! args.state.message.text, "Unknown strategy best, using jc"
end

def test_the_same_seed_starts_the_same_games args, assert
  first  = new_test_game(args, seed: 99)
  first_options = args.state.board.options.map(&:name)
  first.new_game
  first_next = args.state.board.options.map(&:name)

  second = new_test_game(args, seed: 99)
  assert.equal! args.state.board.options.map(&:name), first_options
  second.new_game
  assert.equal! args.state.board.options.map(&:name), first_next
end

def test_try_place_records_undo_and_starts_the_animation args, assert
  game  = new_test_game args
  board = args.state.board
  board.options.replace [tile(:dot), tile(:dot)]
  args.state.selected_option = 0

  assert.true! game.try_place(0, 0, 0)
  assert.equal! board.cells[0][0], 1
  assert.equal! args.state.selected_option, nil
  assert.equal! args.state.history.length, 1
  assert.true! args.state.animation != nil
  assert.false! game.try_place(0, 0, 0)  # (0, 0) is taken now
end

def test_undo_restores_the_board args, assert
  game = new_test_game args
  args.state.board.options.replace [tile(:sq2), tile(:dot)]

  game.try_place 0, 4, 4
  assert.true! game.undo
  assert.equal! args.state.board.score, 0
  assert.equal! args.state.board.options.length, 2
  assert.equal! args.state.animation, nil
  assert.equal! args.state.board.undos_left, Board::UNDOS - 1

  assert.false! game.undo
  assert.equal! args.state.message.text, "Nothing to undo"
  assert.equal! args.state.board.undos_left, Board::UNDOS - 1  # a refused undo costs nothing
end

def test_three_moves_in_a_row_can_be_undone args, assert
  game = new_test_game args
  args.state.board.options.replace [tile(:dot), tile(:dot), tile(:dot)]
  game.try_place 0, 0, 0
  game.try_place 0, 0, 1
  game.try_place 0, 0, 2

  3.times { assert.true! game.undo }
  assert.equal! args.state.board.cells[0].first(3), [0, 0, 0]
  assert.equal! args.state.board.undos_left, 0
end

def test_only_three_undos_per_game args, assert
  game = new_test_game args
  4.times do
    game.auto_move
    game.undo
  end
  assert.equal! args.state.board.undos_left, 0
  assert.equal! args.state.message.text, "No undos left in this game"
  assert.true! args.state.board.score > 0  # the fourth move stayed

  game.new_game
  assert.equal! args.state.board.undos_left, Board::UNDOS
end

def test_undo_after_game_over_restarts_the_game args, assert
  game = new_test_game args
  one_move_from_game_over args.state.board

  game.try_place 0, 0, 0
  assert.true! game.game_over?
  assert.true! args.state.ended_at != nil

  game.undo
  assert.false! game.game_over?
  assert.equal! args.state.ended_at, nil
end

def test_auto_move_places_a_tile args, assert
  game = new_test_game args
  game.auto_move
  assert.true! args.state.board.score > 0
end

def test_computer_can_play_whole_games args, assert
  3.times do |seed|
    game  = new_test_game args, seed: seed
    moves = 0
    until game.game_over? || moves > 1000
      game.auto_move
      moves += 1
    end
    assert.true! game.game_over?
    assert.true! args.state.board.score > 0
  end
end

def test_auto_mode_waits_for_the_animation args, assert
  game = new_test_game args
  args.state.auto = true
  game.update
  score = args.state.board.score
  assert.true! score > 0                # moved
  assert.true! args.state.animation != nil

  args.state.next_auto_at = Kernel.tick_count  # (tick_count can be negative in tests)
  game.update
  assert.equal! args.state.board.score, score  # still animating, so no move

  args.state.animation = nil
  game.update
  assert.true! args.state.board.score > score
end

def test_auto_mode_starts_a_new_game_and_tracks_the_best_score args, assert
  game = new_test_game args
  args.state.auto = true
  args.state.board.options.replace [tile(:sq3)]
  args.state.board.cells.each { |row| row.fill(1) }
  args.state.board.cells[0][0] = Board::EMPTY
  game.refresh_game_over
  old_board = args.state.board

  game.update                          # game over, but it waits a moment first
  assert.true! args.state.board.equal?(old_board)

  args.state.ended_at = Kernel.tick_count - AUTO_RESTART
  game.update
  assert.false! args.state.board.equal?(old_board)
  assert.equal! args.state.auto_runs, 1
end

def test_time_counts_from_when_the_game_opened args, assert
  game = new_test_game args
  args.state.opened_at = Kernel.tick_count - 600  # opened 10 seconds ago
  game.new_game                                   # a new game doesn't reset the clock
  assert.equal! game.play_seconds, 10
end

def test_recording_plays_back_the_same_game args, assert
  game = new_test_game args
  game.toggle_recording
  assert.true! args.state.recording != nil

  5.times { game.auto_move }
  game.undo
  4.times { game.auto_move }
  cells = args.state.board.cells.map(&:dup)
  score = args.state.board.score
  options = args.state.board.options.map(&:name)

  game.start_playback                     # stops the recording, then replays it
  assert.equal! args.state.recording, nil
  assert.equal! args.state.board.score, 0
  steps = 0
  while args.state.playback && steps < 100
    args.state.animation    = nil
    args.state.next_auto_at = Kernel.tick_count
    game.update
    steps += 1
  end

  assert.equal! args.state.board.cells, cells
  assert.equal! args.state.board.score, score
  assert.equal! args.state.board.options.map(&:name), options
  assert.equal! args.state.message.text, "Playback finished"
end

def test_playback_without_a_recording args, assert
  game = new_test_game args
  game.start_playback
  assert.equal! args.state.playback, nil
  assert.equal! args.state.message.text, "Nothing recorded yet (R to record)"
end

def test_a_new_game_ends_a_playback args, assert
  game = new_test_game args
  game.toggle_recording
  game.auto_move
  game.start_playback
  assert.true! args.state.playback != nil

  game.new_game
  assert.equal! args.state.playback, nil
end

def test_keys_call_their_actions args, assert
  game = new_test_game args, game_class: KeyTestGame
  args.inputs.keyboard.key_down.escape = true
  args.inputs.keyboard.key_down.r = true
  args.inputs.keyboard.key_down.h = true
  args.inputs.keyboard.key_down.d = true
  game.handle_keyboard
  assert.equal! game.called, [:quit_without_saving, :toggle_recording]
  assert.true! args.state.show_scores
  assert.equal! args.state.board.skips_left, Board::SKIPS - 1
end

def test_player_keys_are_ignored_while_the_computer_plays args, assert
  game = new_test_game args
  args.state.auto = true
  args.inputs.keyboard.key_down.one = true
  game.handle_keyboard
  assert.equal! args.state.selected_option, nil

  args.state.auto = false
  game.handle_keyboard
  assert.equal! args.state.selected_option, 0
end

def test_save_load_and_delete_the_save_file args, assert
  keeping_the_save_file do
    game = new_test_game args
    game.auto_move
    score = args.state.board.score
    game.save_game

    game.new_game
    game.load_game
    assert.equal! args.state.board.score, score

    # A computer-played session doesn't carry on with the saved game.
    args.state = {}
    auto = Game.new
    auto.args = args
    auto.setup auto: true, strategy: :jc, seed: 1
    assert.equal! args.state.board.score, 0

    # Neither does any session after Esc deleted it.
    game = new_test_game args
    game.delete_save
    assert.equal! DR.read_file(SAVE_FILE), nil
    game.delete_save  # no save file: nothing happens
    game.load_game
    assert.equal! args.state.message.text, "No saved game"
  end
end

def test_effects_expire_outside_of_rendering args, assert
  game = new_test_game args
  args.state.board.options.replace [tile(:dot), tile(:dot)]
  game.try_place 0, 0, 0
  game.show_message "hello"
  args.state.message.at = Kernel.tick_count - MESSAGE_TICKS

  game.expire_finished Kernel.tick_count + MoveAnimation::PLACE_STEP_TICKS
  assert.equal! args.state.animation, nil
  assert.equal! args.state.message, nil
end

def test_mouse_position_maps_to_a_board_square args, assert
  game = new_test_game args
  x, y = game.cell_xy 3, 7
  args.inputs.mouse.x = x + 10
  args.inputs.mouse.y = y + 10
  assert.equal! game.cell_under_mouse, [3, 7]

  args.inputs.mouse.x = 10  # left of the board
  assert.equal! game.cell_under_mouse, nil
end

def test_a_frame_with_a_selected_tile_renders args, assert
  game = new_test_game args
  args.state.selected_option = 0
  args.state.dragging = true
  args.inputs.mouse.x = BOARD_X + 5 * CELL  # over the board
  args.inputs.mouse.y = BOARD_TOP - 5 * CELL
  game.tick
  args.inputs.mouse.x = OPTIONS_X - 20      # off the board, so the tile floats
  game.tick
  assert.true! args.outputs.sprites.length > 300
end

def test_frames_render_while_animating_recording_and_in_auto_mode args, assert
  game = new_test_game args
  game.toggle_recording
  game.auto_move
  args.state.auto = true
  game.tick
  labels = args.outputs.labels.map { |label| label[:text] }
  assert.true! labels.include?("REC")
  assert.true! labels.include?("AUTO: jc")

  game.start_playback
  game.tick
  assert.true! args.outputs.labels.map { |label| label[:text] }.include?("PLAYBACK")
end

def test_format_time args, assert
  game = new_test_game args
  assert.equal! game.format_time(0), "0:00"
  assert.equal! game.format_time(75), "1:15"
end

def test_preview_draws_the_selected_tile_under_the_mouse args, assert
  game = new_test_game args
  args.state.board.options.replace [tile(:br3)]  # 5 squares
  args.state.selected_option = 0
  x, y = game.cell_xy 6, 4
  args.inputs.mouse.x = x + 10
  args.inputs.mouse.y = y + 10

  game.render_preview
  assert.equal! args.outputs.sprites.length, 5 * 3  # each square is 3 rectangles
  assert.equal! args.outputs.sprites.first.a, ALPHA[:preview]
end


# --- Error detection and logging -----------------------------------------------

# The texts logged at `level` since GameLog.count was `start`.
def logged_since start, level
  GameLog.since(start).select { |entry_level, _| entry_level == level }.map { |_, text| text }
end

# An AutoPlayer with a bug: it always chooses a move that can't be made.
class BrokenAutoPlayer < AutoPlayer
  def choose_move _board
    [0, -5, -5]
  end
end

def test_the_log_keeps_entries_by_level args, assert
  start = GameLog.count
  GameLog.info "one"
  GameLog.warn "two"
  GameLog.error "three"
  assert.equal! GameLog.entries.last(3), [[:info, "one"], [:warn, "two"], [:error, "three"]]
  assert.equal! logged_since(start, :warn), ["two"]

  (GameLog::KEEP + 5).times { |i| GameLog.info "filler #{i}" }
  assert.equal! GameLog.entries.length, GameLog::KEEP
end

def test_the_session_seed_and_each_game_over_are_logged args, assert
  start = GameLog.count
  game = new_test_game args, seed: 77
  assert.true! logged_since(start, :info).include?("Session seed 77 (start with --seed 77 to repeat it)")

  player = AutoPlayer.new(:jc, random: Random.new(1))
  args.state.board = Board.new random: Random.new(1)
  play_whole_game player, args.state.board
  game.refresh_game_over
  game.refresh_game_over  # still over: logged only once
  over = logged_since(start, :info).select { |text| text.start_with?("Game over") }
  assert.equal! over, ["Game over with a score of #{args.state.board.score}"]
end

def test_messages_are_logged_and_colored_by_level args, assert
  game = new_test_game args
  start = GameLog.count
  game.show_message "careful", level: :warn
  assert.equal! GameLog.since(start), [[:warn, "careful"]]

  game.render_panel
  label = args.outputs.labels.find { |l| l[:text] == "careful" }
  assert.equal! [label[:r], label[:g], label[:b]], COLORS[:warning].values
end

def test_a_damaged_save_file_is_reported_and_the_game_goes_on args, assert
  keeping_the_save_file do
    game = new_test_game args
    board = args.state.board
    DR.write_file SAVE_FILE, "score=12\nrow=12"
    game.load_game

    assert.true! args.state.board.equal?(board)  # the current game is kept
    assert.equal! args.state.message.level, :error
    assert.equal! args.state.message.text,
                  'The save file is damaged: row 1 is "12", not 10 of the digits 012345'
  end
end

def test_a_failed_save_is_reported_and_q_does_not_quit args, assert
  game  = new_test_game args, save_file: UNWRITABLE_FILE
  start = GameLog.count
  assert.false! game.save_game
  game.save_and_quit  # would end the test run if it quit

  assert.equal! args.state.message.level, :error
  assert.equal! args.state.message.text, "Couldn't save the game to #{UNWRITABLE_FILE} (see #{LOG_FILE})"
  assert.equal! logged_since(start, :error).length, 4  # each failure: what failed, and the exception
end

def test_a_failed_high_score_save_is_reported args, assert
  game = new_test_game args, scores_file: UNWRITABLE_FILE
  one_move_from_game_over args.state.board
  game.try_place 0, 0, 0

  assert.true! game.game_over?
  assert.equal! args.state.leaderboard.best, 1  # still kept in memory
  assert.equal! args.state.message.level, :error
end

def test_a_playback_that_does_not_match_stops_with_an_error args, assert
  game = new_test_game args
  game.toggle_recording
  game.auto_move
  game.stop_recording
  args.state.last_recording.events << [:move, 0, -1, -1]  # can't be played on any board

  game.start_playback
  steps = 0
  while args.state.playback && steps < 10
    args.state.animation    = nil
    args.state.next_auto_at = Kernel.tick_count
    game.update
    steps += 1
  end

  assert.equal! args.state.playback, nil
  assert.equal! args.state.message.level, :error
  assert.equal! args.state.message.text, "Playback stopped: [:move, 0, -1, -1] doesn't work on this board"
  assert.equal! args.state.board.score > 0, true  # the good move before it was replayed
end

def test_a_strategy_that_chooses_a_bad_move_stops_auto_mode args, assert
  game = new_test_game args
  args.state.auto        = true
  args.state.auto_player = BrokenAutoPlayer.new(:jc)
  game.auto_move

  assert.false! args.state.auto
  assert.equal! args.state.board.score, 0
  assert.equal! args.state.message.level, :error
  assert.true! args.state.message.text.start_with?("Bug: the jc player chose [0, -5, -5]")
end

def test_e_after_the_game_is_over_is_not_an_error args, assert
  game = new_test_game args
  args.state.board.options.replace [tile(:dot)]
  Board::ROWS.times { |r| fill_row args.state.board, r }
  game.refresh_game_over
  args.state.message = nil

  game.auto_move
  assert.equal! args.state.message, nil
end

def test_a_crash_is_logged_with_the_seeds_once args, assert
  game = new_test_game args, seed: 5
  start = GameLog.count
  2.times do
    begin
      game.log_crash RuntimeError.new("boom")
    end
  end

  errors = logged_since(start, :error)
  assert.equal! errors.first, "RuntimeError: boom"
  assert.true! errors.any? { |text| text.include?("session seed 5") }
  assert.equal! errors.count("RuntimeError: boom"), 1
end

# --- New tiles (D) ---------------------------------------------------------------

def test_skipping_deals_a_new_set_three_times_per_game args, assert
  game = new_test_game args
  Board::SKIPS.times do
    before = args.state.board.options
    assert.true! game.skip_tiles
    assert.false! args.state.board.options.equal?(before)
    assert.equal! args.state.board.options.length, Board::OPTIONS
  end

  assert.false! game.skip_tiles
  assert.equal! args.state.board.skips_left, 0
  assert.equal! args.state.message.text, "No new tiles left in this game"
end

def test_a_skip_can_be_undone args, assert
  game    = new_test_game args
  options = args.state.board.options.map(&:name)
  game.skip_tiles
  game.undo
  assert.equal! args.state.board.options.map(&:name), options
  assert.equal! args.state.board.skips_left, Board::SKIPS      # the skip comes back...
  assert.equal! args.state.board.undos_left, Board::UNDOS - 1  # ...for a heart
end

def test_skipping_can_end_a_game_over args, assert
  game = new_test_game args
  leave_one_spot args.state.board, tile(:dot)
  args.state.board.options.replace [tile(:sq3)]  # doesn't fit
  game.refresh_game_over
  assert.true! game.game_over?
  assert.true! game.game_over_hint.include?("D: new tiles")

  game.skip_tiles  # the new set always has a small tile that fits, if one can
  assert.false! game.game_over?
end

def test_skips_and_undos_are_recorded_and_played_back args, assert
  game = new_test_game args
  game.toggle_recording
  game.auto_move
  game.skip_tiles
  game.auto_move
  game.undo
  game.auto_move
  cells = args.state.board.cells.map(&:dup)

  game.start_playback
  steps = 0
  while args.state.playback && steps < 20
    args.state.animation    = nil
    args.state.next_auto_at = Kernel.tick_count
    game.update
    steps += 1
  end
  assert.equal! args.state.board.cells, cells
  assert.equal! args.state.message.text, "Playback finished"
end

def test_undos_and_skips_left_are_saved args, assert
  board = Board.new options: [tile(:dot)], undos_left: 1, skips_left: 2
  copy  = Board.from_save board.to_save
  assert.equal! [copy.undos_left, copy.skips_left], [1, 2]

  old_save = board.to_save.split("\n").reject { |line| line.start_with?("undos", "skips") }.join("\n")
  copy = Board.from_save old_save  # from before undos and skips were counted
  assert.equal! [copy.undos_left, copy.skips_left], [Board::UNDOS, Board::SKIPS]

  assert.equal! save_problem(board.to_save.sub("undos=1", "undos=7")), "undos 7 is more than 3"
end

# --- High scores (H) -------------------------------------------------------------

def test_the_leaderboard_keeps_the_best_scores_in_order args, assert
  board = Leaderboard.new
  assert.equal! board.best, 0
  15.times { |i| board.add i * 10, "2026-10-27" }
  assert.equal! board.entries.length, Leaderboard::SIZE
  assert.equal! board.best, 140
  assert.equal! board.entries.last.score, 50
  assert.equal! board.add(5, "2026-10-27"), nil  # not good enough

  twin = board.add 140, "2026-10-27"  # the same score on the same day is a second entry
  assert.equal! board.rank(twin), 2
end

def test_a_game_ending_again_after_an_undo_keeps_its_better_score args, assert
  board = Leaderboard.new
  first = board.add 50, "2026-10-27"
  assert.true! board.add(40, "2026-10-27", replacing: first).equal?(first)
  better = board.add 60, "2026-10-27", replacing: first
  assert.equal! board.entries.map(&:score), [60]
  assert.equal! board.rank(better), 1
end

def test_the_scores_file_is_read_and_bad_lines_reported args, assert
  board, problems = Leaderboard.from_text "30 2026-10-01\n\n120 2026-10-02\nlots of points\n"
  assert.equal! board.entries.map(&:score), [120, 30]
  assert.equal! problems, ['line 4 is not a score: "lots of points"']
  assert.equal! Leaderboard.from_text(board.to_text)[0].entries, board.entries
end

def test_a_finished_game_goes_into_the_high_scores_and_the_file args, assert
  file = "data/1010scores_test.txt"
  game = new_test_game args, scores_file: file
  one_move_from_game_over args.state.board
  game.try_place 0, 0, 0

  assert.true! game.game_over?
  assert.equal! args.state.leaderboard.best, 1
  assert.equal! args.state.message.text, "New high score: 1!"
  assert.equal! DR.read_file(file), "1 #{GameLog.timestamp.split(' ').first}\n"

  new_test_game args, scores_file: file  # a new session reads it back
  assert.equal! args.state.leaderboard.best, 1
ensure
  DR.delete_file file if DR.stat_file(file)
end

def test_loading_a_finished_game_does_not_record_it_again args, assert
  keeping_the_save_file do
    game = new_test_game args
    one_move_from_game_over args.state.board
    game.try_place 0, 0, 0
    game.save_game
    game.load_game
    game.load_game

    assert.true! game.game_over?
    assert.equal! args.state.leaderboard.entries.length, 1
  end
end

def test_games_the_computer_plays_are_not_high_scores args, assert
  game = new_test_game args
  args.state.auto = true
  one_move_from_game_over args.state.board
  game.try_place 0, 0, 0
  assert.true! game.game_over?
  assert.equal! args.state.leaderboard.entries, []
end

def test_h_shows_the_high_scores_instead_of_the_help args, assert
  game = new_test_game args
  args.state.leaderboard.add 77, "2026-10-27"
  game.toggle_scores
  game.tick
  texts = args.outputs.labels.map { |label| label[:text] }
  assert.true! texts.include?("High scores (H: help)")
  assert.true! texts.include?("77")
  assert.true! texts.include?("Your best: 77")
  assert.false! texts.include?(HELP_LINES.first)

  game.toggle_scores
  args.outputs.labels.clear
  game.tick
  assert.true! args.outputs.labels.map { |label| label[:text] }.include?(HELP_LINES.first)
end

def test_a_heart_is_drawn_per_undo_and_grays_when_used args, assert
  game = new_test_game args
  game.auto_move
  game.undo
  game.render_undo_hearts

  pixels = HEART.cells.length
  colors = args.outputs.sprites.map { |sprite| [sprite[:r], sprite[:g], sprite[:b]] }
  assert.equal! colors.count(COLORS[:heart].values), pixels * (Board::UNDOS - 1)
  assert.equal! colors.count(COLORS[:used_heart].values), pixels
end
