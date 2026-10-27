# Unit tests for the game rules in app/main.rb.
# Run from the tic-tac-toe folder:
#   ./dragonruby mygame --test tests/tic_tac_toe_tests.rb
#
# Every method named test_* is run with a fresh `args` and an `assert` object.

def test_no_winner_on_empty_board args, assert
  assert.equal! find_winning_line(Array.new(9)), nil
end

def test_finds_row_column_and_diagonal_wins args, assert
  assert.equal! find_winning_line([:x, :x, :x, nil, nil, nil, nil, nil, nil]), [0, 1, 2]
  assert.equal! find_winning_line([:o, nil, nil, :o, nil, nil, :o, nil, nil]), [0, 3, 6]
  assert.equal! find_winning_line([nil, nil, :x, nil, :x, nil, :x, nil, nil]), [2, 4, 6]
end

def test_mixed_line_is_not_a_win args, assert
  assert.equal! find_winning_line([:x, :o, :x, nil, nil, nil, nil, nil, nil]), nil
end

def test_players_alternate args, assert
  boot args
  play_move args, 4
  assert.equal! args.state.board[4], :x
  assert.equal! args.state.current_player, :o
end

def test_win_updates_winner_and_score args, assert
  boot args
  [0, 3, 1, 4, 2].each { |index| play_move args, index }  # X takes the bottom row
  assert.equal! args.state.winner, :x
  assert.equal! args.state.winning_line, [0, 1, 2]
  assert.equal! args.state.scores[:x], 1
end

def test_full_board_without_winner_is_a_draw args, assert
  boot args
  # X O X
  # X O O
  # O X X   (listed bottom row first, matching the board indexes)
  [0, 1, 2, 4, 3, 6, 8, 5, 7].each { |index| play_move args, index }
  assert.equal! args.state.winner, :draw
  assert.equal! args.state.scores[:draw], 1
end

def test_cell_rects_line_up_with_board args, assert
  assert.equal! cell_rect(0).x, BOARD_X + CELL_GAP.idiv(2)
  assert.equal! cell_rect(0).y, BOARD_Y + CELL_GAP.idiv(2)
  assert.equal! cell_rect(8).x, BOARD_X + 2 * CELL_SIZE + CELL_GAP.idiv(2)
  assert.equal! cell_rect(8).y, BOARD_Y + 2 * CELL_SIZE + CELL_GAP.idiv(2)
end

def test_mouse_position_maps_to_the_right_square args, assert
  rect = cell_rect(7)  # top-middle square
  args.inputs.mouse.x = rect.x + 10
  args.inputs.mouse.y = rect.y + 10
  assert.equal! cell_under_mouse(args), 7

  args.inputs.mouse.x = 10  # far left, off the board
  assert.equal! cell_under_mouse(args), nil
end

# --- Computer player -------------------------------------------------------

def test_computer_takes_a_winning_move args, assert
  # O has 0 and 1, so 2 wins. X also threatens 3-4-5, but winning comes first.
  board = [:o, :o, nil, :x, :x, nil, nil, nil, nil]
  assert.equal! choose_computer_move(board, :o), 2
end

def test_computer_blocks_the_opponent args, assert
  # X has 0 and 4, so O must take 8.
  board = [:x, nil, nil, nil, :x, nil, nil, :o, nil]
  assert.equal! choose_computer_move(board, :o), 8
end

def test_computer_prefers_center_then_corners args, assert
  assert.equal! choose_computer_move(Array.new(9), :o), CENTER

  board = Array.new(9)
  board[CENTER] = :x
  assert.true! CORNERS.include?(choose_computer_move(board, :o))
end

def test_computer_always_picks_an_empty_square args, assert
  board = [:x, :o, :x, :x, :o, :o, :o, :x, nil]
  assert.equal! choose_computer_move(board, :o), 8
end

def test_computer_waits_before_moving args, assert
  boot args
  args.state.current_player = COMPUTER
  args.state.turn_started_at = Kernel.tick_count  # its turn just started
  update_computer args
  assert.equal! args.state.board.compact.length, 0

  args.state.turn_started_at = Kernel.tick_count - COMPUTER_DELAY  # it has waited long enough
  update_computer args
  assert.equal! args.state.board.compact.length, 1
  assert.equal! args.state.current_player, HUMAN
end

def test_two_player_mode_has_no_computer args, assert
  boot args
  switch_mode args
  args.state.current_player = COMPUTER
  args.state.turn_started_at = Kernel.tick_count - COMPUTER_DELAY
  update_computer args
  assert.equal! args.state.board.compact.length, 0
end
