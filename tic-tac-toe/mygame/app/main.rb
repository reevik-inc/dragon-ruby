# Tic-Tac-Toe: a small DragonRuby Game Toolkit game to study.
#
# How a DragonRuby game runs:
#   - `boot` is called once, when the game starts.
#   - `tick` is called 60 times per second. Each tick we:
#       1. read input           (args.inputs)
#       2. update the game      (args.state)
#       3. describe the screen  (args.outputs)
#   - Nothing stays on screen by itself: every frame we render everything again.
#
# The screen is 1280x720 logical pixels and (0, 0) is the BOTTOM-left corner,
# so y grows upwards.
#
# Save this file while the game is running and your changes are hot-loaded.
# Open the console with the ` (backtick) key and type `$state` to inspect state.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

CELL_SIZE  = 180              # each square takes up 180x180 px...
CELL_GAP   = 10               # ...minus a gap; the background shows through as grid lines
BOARD_SIZE = CELL_SIZE * 3    # 540
BOARD_X    = (1280 - BOARD_SIZE).idiv 2  # 370: centers the board horizontally
BOARD_Y    = 60                       # leaves room above the board for the status text

# In one player mode you are X and the computer is O.
HUMAN    = :x
COMPUTER = :o

# The computer waits this many ticks before moving (60 ticks = 1 second),
# otherwise its mark would appear in the same frame as yours.
COMPUTER_DELAY = 40

# The board is a flat array of 9 cells. index = row * 3 + column.
# Row 0 is the BOTTOM row, because y grows upwards:
#
#   6 | 7 | 8
#   3 | 4 | 5
#   0 | 1 | 2
#
# These are the 8 ways to win, as lists of board indexes.
WINNING_LINES = [
  [0, 1, 2], [3, 4, 5], [6, 7, 8], # rows
  [0, 3, 6], [1, 4, 7], [2, 5, 8], # columns
  [0, 4, 8], [2, 4, 6]             # diagonals
]

CENTER  = 4
CORNERS = [0, 2, 6, 8]

COLORS = {
  background: { r: 30,  g: 30,  b: 40  },
  cell:       { r: 60,  g: 60,  b: 75  },
  cell_hover: { r: 85,  g: 85,  b: 105 },
  cell_win:   { r: 230, g: 190, b: 70  },
  x:          { r: 240, g: 90,  b: 90  },
  o:          { r: 90,  g: 170, b: 240 },
  text:       { r: 230, g: 230, b: 230 },
  dim_text:   { r: 150, g: 150, b: 165 }
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

def boot args
  args.state = {}
  args.state.mode = :one_player                # or :two_player (press M to switch)
  args.state.scores = { x: 0, o: 0, draw: 0 }  # kept across rounds
  args.state.starting_player = :x
  start_round args
end

# Everything that is cleared at the start of each round.
def start_round args
  args.state.board          = Array.new(9)   # nil = empty, otherwise :x or :o
  args.state.current_player = args.state.starting_player
  args.state.winner         = nil            # nil while playing, then :x, :o, or :draw
  args.state.winning_line   = nil            # e.g. [0, 4, 8] once someone wins
  args.state.turn_started_at = Kernel.tick_count
end

# ---------------------------------------------------------------------------
# The game loop
# ---------------------------------------------------------------------------

def tick args
  handle_input args
  update_computer args
  render args
end

# ---------------------------------------------------------------------------
# Input and game rules
# ---------------------------------------------------------------------------

def handle_input args
  if args.inputs.keyboard.key_down.m
    switch_mode args
    return
  end

  # key_down is only true on the single frame the button was pressed,
  # so one click places exactly one mark.
  clicked = args.inputs.mouse.key_down.left

  if round_over? args
    if clicked || args.inputs.keyboard.key_down.space
      # Take turns going first so the game stays fair.
      args.state.starting_player = other_player args.state.starting_player
      start_round args
    end
    return
  end

  return unless clicked
  return if computers_turn? args     # ignore clicks while the computer is thinking

  index = cell_under_mouse args
  return if index.nil?               # clicked outside the board
  return if args.state.board[index]  # square is already taken

  play_move args, index
end

def switch_mode args
  args.state.mode = args.state.mode == :one_player ? :two_player : :one_player
  args.state.scores = { x: 0, o: 0, draw: 0 }  # scores mean something different per mode
  args.state.starting_player = :x
  start_round args
end

def play_move args, index
  player = args.state.current_player
  args.state.board[index] = player

  line = find_winning_line args.state.board
  if line
    args.state.winner = player
    args.state.winning_line = line
    args.state.scores[player] += 1
  elsif args.state.board.all?  # no empty (nil) squares left
    args.state.winner = :draw
    args.state.scores[:draw] += 1
  else
    args.state.current_player = other_player player
    args.state.turn_started_at = Kernel.tick_count
  end
end

# Returns the winning line (e.g. [2, 4, 6]) or nil if nobody has won yet.
def find_winning_line board
  WINNING_LINES.find do |a, b, c|
    board[a] && board[a] == board[b] && board[a] == board[c]
  end
end

def other_player player
  player == :x ? :o : :x
end

def round_over? args
  !args.state.winner.nil?
end

def one_player? args
  args.state.mode == :one_player
end

def computers_turn? args
  one_player?(args) && !round_over?(args) && args.state.current_player == COMPUTER
end

# ---------------------------------------------------------------------------
# Computer player
# ---------------------------------------------------------------------------

# Called every tick. Most ticks it does nothing; once the computer has
# "thought" for COMPUTER_DELAY ticks, it makes its move.
def update_computer args
  return unless computers_turn? args
  return if Kernel.tick_count < args.state.turn_started_at + COMPUTER_DELAY

  play_move args, choose_computer_move(args.state.board, COMPUTER)
end

# Picks a square using the same simple rules a person might follow,
# checked in order:
#   1. If I can win right now, do it.
#   2. If my opponent could win on their next move, block them.
#   3. Take the center.
#   4. Take a corner.
#   5. Take any empty square.
# This plays well but can be beaten (try setting up two threats at once).
def choose_computer_move board, me
  empty = empty_squares board

  completing_move(board, me) ||
    completing_move(board, other_player(me)) ||
    (CENTER if empty.include? CENTER) ||
    (CORNERS & empty).sample ||
    empty.sample
end

# Finds a square that would give `player` three in a row: a line where
# they already have two squares and the third is empty. Returns nil if none.
def completing_move board, player
  WINNING_LINES.each do |line|
    marks = line.map { |index| board[index] }
    if marks.count(player) == 2 && marks.count(nil) == 1
      return line[marks.index(nil)]
    end
  end
  nil
end

def empty_squares board
  (0..8).select { |index| board[index].nil? }
end

# ---------------------------------------------------------------------------
# Board geometry
# ---------------------------------------------------------------------------

# The rectangle (x, y, w, h) for a board index. Rendering and mouse
# hit-testing both use this, so they can never disagree.
def cell_rect index
  # NOTE: in DragonRuby, Integer / Integer returns a Float (8 / 3 == 2.666...),
  # unlike standard Ruby. idiv does integer division: 8.idiv(3) == 2.
  row    = index.idiv 3  # 0, 1 or 2
  column = index % 3
  {
    x: BOARD_X + column * CELL_SIZE + CELL_GAP.idiv(2),
    y: BOARD_Y + row    * CELL_SIZE + CELL_GAP.idiv(2),
    w: CELL_SIZE - CELL_GAP,
    h: CELL_SIZE - CELL_GAP
  }
end

# The index of the square under the mouse, or nil if it's not over the board.
def cell_under_mouse args
  (0..8).find { |index| args.inputs.mouse.inside_rect? cell_rect(index) }
end

# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

def render args
  args.outputs.background_color = COLORS[:background]
  render_board args
  render_status args
  render_side_panels args
end

def render_board args
  # Only highlight the square under the mouse when a click would do something.
  can_click = !round_over?(args) && !computers_turn?(args)
  hovered = can_click ? cell_under_mouse(args) : nil
  winning_line = args.state.winning_line || []

  9.times do |index|
    rect = cell_rect index
    mark = args.state.board[index]
    won  = winning_line.include? index

    color = if won
              COLORS[:cell_win]
            elsif index == hovered && mark.nil?
              COLORS[:cell_hover]
            else
              COLORS[:cell]
            end

    # `path: :solid` turns a sprite into a plain colored rectangle.
    args.outputs.sprites << rect.merge(path: :solid).merge(color)

    next if mark.nil?

    args.outputs.labels << {
      x: rect.x + rect.w / 2,  # anchor 0.5 centers the text on this point
      y: rect.y + rect.h / 2,
      text: mark.to_s.upcase,
      size_px: 140,
      anchor_x: 0.5,
      anchor_y: 0.5
    }.merge(won ? COLORS[:background] : COLORS[mark])
  end
end

def render_status args
  args.outputs.labels << { x: 640, y: 660, text: status_text(args), size_px: 44,
                           anchor_x: 0.5, anchor_y: 0.5 }.merge(status_color(args))

  if round_over? args
    args.outputs.labels << { x: 640, y: 30, text: "Click or press Space to play again",
                             size_px: 22, anchor_x: 0.5, anchor_y: 0.5 }.merge(COLORS[:dim_text])
  end
end

def status_text args
  winner = args.state.winner
  player = args.state.current_player

  if winner == :draw
    "It's a draw!"
  elsif one_player? args
    if    winner == HUMAN    then "You win!"
    elsif winner == COMPUTER then "The computer wins!"
    elsif player == HUMAN    then "Your turn (X)"
    else                          "The computer is thinking..."
    end
  else
    winner ? "#{winner.to_s.upcase} wins!" : "#{player.to_s.upcase}'s turn"
  end
end

def status_color args
  player = args.state.winner || args.state.current_player
  COLORS[player] || COLORS[:text]  # COLORS[:draw] is nil, so a draw uses the text color
end

def render_side_panels args
  scores = args.state.scores
  x_name, o_name = one_player?(args) ? ["You", "Computer"] : ["X", "O"]

  render_lines args, x: 185, y: 480, lines: [
    ["Score",                     COLORS[:text]],
    ["#{x_name}: #{scores[:x]}",  COLORS[:x]],
    ["#{o_name}: #{scores[:o]}",  COLORS[:o]],
    ["Draws: #{scores[:draw]}",   COLORS[:dim_text]]
  ]

  mode_name   = one_player?(args) ? "1 player" : "2 players"
  other_mode = one_player?(args) ? "2 players" : "1 player"

  render_lines args, x: 1095, y: 480, lines: [
    ["Mode: #{mode_name}",        COLORS[:text]],
    ["Click a square",            COLORS[:dim_text]],
    ["Get 3 in a row",            COLORS[:dim_text]],
    ["M: switch to #{other_mode}", COLORS[:dim_text]]
  ]
end

# Draws a column of centered labels, top to bottom, starting at y.
def render_lines args, x:, y:, lines:
  lines.each_with_index do |(text, color), i|
    args.outputs.labels << { x: x, y: y - i * 44, text: text, size_px: 30,
                             anchor_x: 0.5, anchor_y: 0.5 }.merge(color)
  end
end
