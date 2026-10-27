# 1010!: a DragonRuby port of the Gosu game at https://github.com/shanko/1010
#
# The game is split into these files:
#   app/tiles.rb           the 19 tile shapes                 (Board1010::TILES)
#   app/board.rb           the rules, no drawing at all       (class Board1010)
#   app/auto_player.rb     how the computer picks its moves   (class AutoPlayer)
#   app/move_animation.rb  shows a move square by square      (class MoveAnimation)
#   app/main.rb            input, auto play and drawing       (class GameWindow)
#
# Start options (all optional):
#   ./dragonruby mygame --auto              the computer plays, game after game
#   ./dragonruby mygame --auto sam          ...with another strategy (see auto_player.rb)
#   ./dragonruby mygame --auto --seed 42    the same tiles and moves every run
#
# Gosu calls `update` and `draw` on a Window object. DragonRuby instead calls
# the top-level `tick` method 60 times per second. Ours hands each tick to a
# Game object (at the bottom of this file), which reads input, changes the
# game, then describes what to draw.
#
# DragonRuby's (0, 0) is the BOTTOM-left of the 1280x720 screen and y grows
# upwards. The board keeps the original's numbering (row 0 at the top), so
# `cell_xy` converts rows into y positions measured down from BOARD_TOP.

require "app/tiles.rb"
require "app/board.rb"
require "app/auto_player.rb"
require "app/move_animation.rb"

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

CELL        = 60                 # space taken by one board square...
CELL_GAP    = 4                  # ...of which this much is the gap between squares
CELL_INNER  = CELL - CELL_GAP    # the visible part of a square
CORNER      = 4                  # size of the clipped corners on each square
BOARD_X     = 60
BOARD_TOP   = 660
BOARD_SIZE  = CELL * Board::COLS # 600
BOARD_FRAME = 6                  # width of the gray frame around the board

# The 3 tiles to choose from ("options", like the original), stacked
# top to bottom to the right of the board.
OPTIONS_X           = 700
OPTION_W            = 250
OPTION_H            = 190
OPTION_STEP         = 200        # distance from one option to the next
OPTION_CELL         = 34         # tiles are drawn smaller here than on the board
OPTION_CELL_INNER   = 30
OPTION_CORNER       = 3
OPTION_NUMBER_INSET = 14         # where the 1/2/3 sits, from the top-left corner

# The panel on the right: score, status and help.
PANEL_X        = 990
PANEL_W        = 240
PANEL_CENTER_X = PANEL_X + PANEL_W.idiv(2)
PANEL_Y = {
  title:       650,
  score:       570,
  time:        525,
  status:      480,
  status_hint: 448,
  mode:        410,  # AUTO or PLAYBACK
  mode_detail: 384,
  help:        350
}
HELP_LINE_HEIGHT = 26
RECORDING_MARK_X = PANEL_X + 150  # next to the time
RECORDING_MARK   = 16

# Messages like "Game saved" go below the board, where long ones fit.
MESSAGE_X = BOARD_X
MESSAGE_Y = 28

HELP_LINES = [
  "Drag a tile onto the board,",
  "or pick one (click or 1/2/3)",
  "then click a square.",
  "Right click: drop selection",
  "",
  "O (hold): best spot for tile",
  "U: undo     N: new game",
  "A: auto play  E: one move",
  "S: save     L: load",
  "R: record   P: play it back",
  "C: print fits to console",
  "Q: save and quit",
  "Esc: quit, delete the save"
]

# Keys that work at any time, and the method each one calls.
KEY_ACTIONS = {
  escape: :quit_without_saving,
  q:      :save_and_quit,
  a:      :toggle_auto,
  n:      :new_game,
  s:      :save_game,
  l:      :load_game,
  r:      :toggle_recording,
  p:      :start_playback,
  c:      :print_positions
}

# Keys that make moves, ignored while the computer or a playback is playing.
PLAYER_ACTIONS = {
  e: :auto_move,  # let the computer make one move
  u: :undo
}

OPTION_KEYS = { one: 0, two: 1, three: 2 }

# ---------------------------------------------------------------------------
# Timing and files
# ---------------------------------------------------------------------------

AUTO_DELAY    = 8    # ticks between computer (and playback) moves, after the animation
AUTO_RESTART  = 90   # ticks to show "Game over" before auto mode starts again
MESSAGE_TICKS = 120  # how long messages like "Game saved" stay up
BLINK_TICKS   = 15   # how fast the recording mark blinks

SAVE_FILE = "data/1010game.txt"  # relative to the mygame folder

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------

COLORS = {
  background:      { r: 250, g: 250, b: 245 },
  board:           { r: 150, g: 150, b: 150 },  # the gray frame around the board
  empty:           { r: 222, g: 240, b: 218 },
  option:          { r: 236, g: 236, b: 230 },
  option_selected: { r: 255, g: 243, b: 190 },
  selected:        { r: 250, g: 200, b: 0   },  # the original turned the selected tile yellow
  hint:            { r: 217, g: 17,  b: 152 },
  invalid:         { r: 200, g: 60,  b: 60  },
  score:           { r: 220, g: 30,  b: 30  },  # the original used red text
  text:            { r: 50,  g: 50,  b: 60  },
  dim_text:        { r: 120, g: 120, b: 130 }
}

# Colors by tile value, like GameWindow#cell_color.
TILE_COLORS = {
  1 => { r: 27,  g: 184, b: 139 },  # green
  2 => { r: 236, g: 85,  b: 37  },  # orange
  3 => { r: 230, g: 40,  b: 220 },  # fuchsia
  4 => { r: 119, g: 47,  b: 192 },  # purple
  5 => { r: 5,   g: 145, b: 245 }   # blue
}

# How see-through things are drawn (255 = solid, 0 = invisible).
ALPHA = {
  opaque:    255,
  preview:   130,  # where the selected tile would land
  blocked:   90,   # ...in red, when it doesn't fit there
  hint:      200,  # the computer's suggestion (hold O)
  dragged:   220,  # the tile following the mouse
  picked_up: 70,   # the dragged tile's empty spot among the options
  unusable:  80    # an option that doesn't fit anywhere on the board
}

class Game
  # attr_dr gives this class `args`, `state`, `inputs` and `outputs`, so the
  # methods below don't have to pass `args` around.
  attr_dr

  # -------------------------------------------------------------------------
  # Setup
  # -------------------------------------------------------------------------

  # `options` come from the command line (see options_from); tests pass their own.
  def setup(options = Game.options_from(GTK.cli_arguments))
    # Every game's seed comes from here, so --seed repeats a whole session.
    state.seeds          = Random.new(options[:seed] || rand(2**31))
    state.auto_player    = auto_player_for options[:strategy]
    state.auto           = options[:auto]  # computer plays (A)
    state.auto_runs      = 0               # games finished in auto mode
    state.auto_best      = 0               # best auto score so far
    state.recording      = nil             # { seed:, events: } of the game being recorded
    state.last_recording = nil
    state.playback       = nil             # events still to replay
    state.opened_at      = Kernel.tick_count  # for the time played, over every game

    # Like the original, carry on with a saved game if there is one.
    load_game quiet: true unless state.auto
    new_game unless state.board
  end

  # Reads `--auto [strategy] --seed N` from the command line.
  # (DragonRuby gives a bare `--auto` the value nil.)
  def self.options_from cli
    options = { auto: cli.key?(:auto), strategy: cli[:auto] || AutoPlayer::DEFAULT_STRATEGY }
    options[:seed] = cli[:seed].to_i if cli[:seed]
    options
  end

  def auto_player_for strategy
    AutoPlayer.new strategy, random: Random.new(next_seed)
  rescue ArgumentError => e
    puts e.message
    show_message "#{e.message.split(',').first}, using #{AutoPlayer::DEFAULT_STRATEGY}"
    AutoPlayer.new AutoPlayer::DEFAULT_STRATEGY, random: Random.new(next_seed)
  end

  def next_seed
    state.seeds.rand(2**32)
  end

  # NOTE: state is a Hash read with dots (state.board). If a key has the same
  # name as a Hash method (like `size`) or a top-level method (like `tick`),
  # the METHOD wins. Keeping our methods inside this class avoids most clashes.
  def new_game(seed: next_seed)
    board = Board.new random: Random.new(seed)
    board.deal_if_needed
    start board, seed: seed
  end

  # Everything that is reset when a game starts (new, loaded or played back).
  def start board, seed: nil
    stop_recording
    state.board           = board
    state.seed            = seed   # nil for a loaded game, which can't be recorded
    state.previous_board  = nil    # for undo (one level, like the original)
    state.selected_option = nil    # index of the chosen tile in board.options
    state.dragging        = false  # is the chosen tile being dragged?
    state.animation       = nil    # the MoveAnimation of the last move
    state.playback        = nil    # a new game also ends a playback
    state.ended_at        = nil
    state.next_auto_at    = Kernel.tick_count
    refresh_game_over
  end

  # Call after every change to the board. (Checking every frame would mean
  # trying every tile on every square 60 times a second.)
  def refresh_game_over
    state.game_over = state.board.game_over?
    state.ended_at  = state.game_over ? (state.ended_at || Kernel.tick_count) : nil
  end

  # -------------------------------------------------------------------------
  # The game loop
  # -------------------------------------------------------------------------

  def tick
    setup if state.board.nil?  # the first tick (and after DR.reset)
    handle_keyboard
    handle_mouse
    update
    render
  end

  def game_over?
    state.game_over
  end

  def selected_tile
    state.selected_option && state.board.options[state.selected_option]
  end

  # Moves the computer or the playback along. (Kept out of the render
  # methods, so drawing never changes the game.)
  def update
    now = Kernel.tick_count
    expire_finished now
    return if state.animation  # let a move finish before the next automatic one
    return if now < state.next_auto_at

    if state.playback
      play_back_next
    elsif state.auto
      auto_step now
    end
  end

  # Drops the move animation and the message once their time is up.
  def expire_finished now
    animation = state.animation
    state.animation = nil if animation && animation.done?(now)

    message = state.message
    state.message = nil if message && now - message.at >= MESSAGE_TICKS
  end

  # -------------------------------------------------------------------------
  # Input
  # -------------------------------------------------------------------------

  # Looks each key pressed this frame up in KEY_ACTIONS, PLAYER_ACTIONS and
  # OPTION_KEYS. (key_down is true only on the frame a key is pressed.)
  def handle_keyboard
    keys = inputs.keyboard.key_down

    KEY_ACTIONS.each { |key, action| send action if keys.send(key) }
    return if state.auto || state.playback  # the rest would interfere with the computer

    PLAYER_ACTIONS.each { |key, action| send action if keys.send(key) }
    OPTION_KEYS.each { |key, index| select_option index if keys.send(key) }
  end

  # Two ways to place a tile, as in the original:
  #   - drag it from the options and let go over the board, or
  #   - click it (or press 1/2/3), then click a square on the board.
  # Either way the tile is placed when the mouse button is RELEASED over the board.
  def handle_mouse
    mouse = inputs.mouse
    return if state.auto || state.playback || game_over?

    if mouse.key_down.left
      index = option_under_mouse
      if index
        state.selected_option = index
        state.dragging        = true
      end
    end

    if mouse.key_up.left
      state.dragging = false
      row, col = cell_under_mouse
      try_place state.selected_option, row, col if state.selected_option && row
    end

    state.selected_option = nil if mouse.key_down.right
  end

  def select_option index
    return if game_over?
    state.selected_option = index if index < state.board.options.length
  end

  # C: prints the first position where each option fits (for debugging).
  def print_positions
    state.board.options.each_with_index do |tile, index|
      puts "Option #{index + 1} #{tile.name} fits first at #{state.board.find_position(tile).inspect}"
    end
  end

  # -------------------------------------------------------------------------
  # Playing a move
  # -------------------------------------------------------------------------

  # Plays option `index` with its anchor on (row, col), for the player, the
  # computer and playback alike. Board#play does the rules; this method only
  # updates what the screen needs. Returns false if the tile doesn't fit.
  def try_place index, row, col
    before = state.board.copy
    move   = state.board.play index, row, col
    return false unless move

    state.previous_board  = before  # one level of undo, like the original
    state.recording.events << [:move, index, row, col] if state.recording
    state.selected_option = nil
    clear_step = state.auto ? MoveAnimation::PLACE_STEP_TICKS : MoveAnimation::CLEAR_STEP_TICKS
    state.animation = MoveAnimation.new move, Kernel.tick_count, clear_step: clear_step
    refresh_game_over
    true
  end

  def undo
    return show_message("Nothing to undo") unless state.previous_board

    state.board           = state.previous_board
    state.previous_board  = nil
    state.selected_option = nil
    state.animation       = nil
    state.recording.events << [:undo] if state.recording
    refresh_game_over
  end

  # -------------------------------------------------------------------------
  # Auto mode (the computer plays)
  # -------------------------------------------------------------------------

  def toggle_auto
    state.auto            = !state.auto
    state.selected_option = nil
    state.dragging        = false
  end

  # Like the original, auto mode keeps starting new games, tracking the
  # number of runs and the best score.
  def auto_step now
    unless game_over?
      auto_move
      state.next_auto_at = now + AUTO_DELAY  # so you can watch
      return
    end
    return if now < state.ended_at + AUTO_RESTART

    state.auto_runs += 1
    if state.board.score > state.auto_best
      state.auto_best = state.board.score
      puts "Score = #{state.auto_best}"
    end
    new_game
  end

  # The strategy is in auto_player.rb (jc unless --auto names another).
  def auto_move
    move = state.auto_player.choose_move state.board
    try_place(*move) if move
  end

  # -------------------------------------------------------------------------
  # Recording and playback
  # -------------------------------------------------------------------------

  # R starts recording a new game; pressing R again stops.
  def toggle_recording
    return stop_recording if state.recording

    new_game
    state.recording = { seed: state.seed, events: [] }
    show_message "Recording a new game (R to stop)"
  end

  def stop_recording
    return unless state.recording

    state.last_recording = state.recording
    state.recording      = nil
    show_message "Recording stopped (P to play it back)"
  end

  # P plays the last recording: the same tiles (from its seed) and the same moves.
  def start_playback
    stop_recording
    return show_message("Nothing recorded yet (R to record)") unless state.last_recording

    recording = state.last_recording
    new_game seed: recording.seed
    state.auto     = false
    state.playback = recording.events.dup
  end

  def play_back_next
    event = state.playback.shift
    case event && event[0]
    when :move then try_place event[1], event[2], event[3]
    when :undo then undo
    else
      state.playback = nil
      show_message "Playback finished"
    end
    state.next_auto_at = Kernel.tick_count + AUTO_DELAY
  end

  # -------------------------------------------------------------------------
  # Saving and quitting
  # -------------------------------------------------------------------------

  def save_game
    DR.write_file SAVE_FILE, state.board.to_save
    show_message "Game saved"
  end

  def load_game quiet: false
    text = DR.read_file SAVE_FILE  # nil if there is no save file
    if text.nil?
      show_message "No saved game" unless quiet
      return
    end

    board = Board.from_save text, random: Random.new(next_seed)
    if board.nil?
      show_message "The save file is damaged"
      return
    end

    board.deal_if_needed
    start board
    show_message "Loaded the saved game (N starts a new one)"
  end

  def show_message text
    state.message = { text: text, at: Kernel.tick_count }
    nil
  end

  def save_and_quit
    save_game
    DR.request_quit
  end

  # Esc: deletes the saved game too, so the next start is a new game.
  def quit_without_saving
    delete_save
    DR.request_quit
  end

  def delete_save
    DR.delete_file SAVE_FILE if DR.stat_file(SAVE_FILE)
  end

  # Called by `shutdown` when the game exits (Esc, Q or closing the window),
  # like GameWindow#close.
  def print_summary
    return unless state.board

    puts "Total time played = #{play_seconds} seconds"
    puts "Score = #{state.board.score}"
  end

  # -------------------------------------------------------------------------
  # Screen geometry
  # -------------------------------------------------------------------------

  # [x, y] of the bottom-left corner of a board square. Rows count DOWN from
  # BOARD_TOP.
  def cell_xy row, col
    [BOARD_X + col * CELL + CELL_GAP.idiv(2),
     BOARD_TOP - (row + 1) * CELL + CELL_GAP.idiv(2)]
  end

  # [row, col] of the board square under the mouse, or nil.
  # NOTE: dividing in DragonRuby gives a Float, so .floor turns it into a
  # whole square number (and rounds negatives down, so they stay off the board).
  def cell_under_mouse
    mouse = inputs.mouse
    col = ((mouse.x - BOARD_X) / CELL).floor
    row = ((BOARD_TOP - mouse.y) / CELL).floor
    [row, col] if state.board.inside?(row, col)
  end

  # The rectangle of option 0, 1 or 2 (top to bottom).
  def option_rect index
    { x: OPTIONS_X, y: BOARD_TOP - OPTION_H - index * OPTION_STEP, w: OPTION_W, h: OPTION_H }
  end

  def option_under_mouse
    (0...state.board.options.length).find { |i| inputs.mouse.inside_rect? option_rect(i) }
  end

  # -------------------------------------------------------------------------
  # Rendering (only draws; never changes the game)
  # -------------------------------------------------------------------------

  def render
    outputs.background_color = COLORS[:background]
    render_board
    render_preview
    render_options
    render_dragged_tile
    render_panel
    render_recording_mark
  end

  def render_board
    outputs.sprites << { x: BOARD_X - BOARD_FRAME,
                         y: BOARD_TOP - BOARD_SIZE - BOARD_FRAME,
                         w: BOARD_SIZE + 2 * BOARD_FRAME,
                         h: BOARD_SIZE + 2 * BOARD_FRAME,
                         path: :solid }.merge(COLORS[:board])

    # While a move is animated, squares show what the animation says
    # (the tile appearing, then full lines emptying one by one).
    now       = Kernel.tick_count
    animation = state.animation
    state.board.cells.each_with_index do |row_values, row|
      row_values.each_with_index do |value, col|
        value = animation.value_at(row, col, value, now) if animation
        board_square row, col, value == Board::EMPTY ? COLORS[:empty] : TILE_COLORS[value]
      end
    end
  end

  # Shows where the selected tile would land (in its own color if it fits,
  # red if not), and while O is held, the spot the computer would pick with
  # its current strategy (like the original's "show position").
  def render_preview
    tile = selected_tile
    return unless tile

    board = state.board
    row, col = cell_under_mouse
    if row
      if board.fits?(tile, row, col)
        board_squares board.cells_for(tile, row, col), TILE_COLORS[tile.value], alpha: ALPHA[:preview]
      else
        board_squares board.cells_for(tile, row, col), COLORS[:invalid], alpha: ALPHA[:blocked]
      end
    end

    if inputs.keyboard.o
      best = state.auto_player.best_position board, tile
      board_squares board.cells_for(tile, *best), COLORS[:hint], alpha: ALPHA[:hint] if best
    end
  end

  def render_options
    board = state.board

    Board::OPTIONS.times do |i|
      rect     = option_rect i
      tile     = board.options[i]
      selected = state.selected_option == i

      outputs.sprites << rect.merge(path: :solid).merge(selected ? COLORS[:option_selected] : COLORS[:option])
      label rect.x + OPTION_NUMBER_INSET, rect.y + rect.h - OPTION_NUMBER_INSET, (i + 1).to_s,
            size: 18, color: :dim_text, anchor_x: 0.5
      next unless tile

      # Selected tiles turn yellow; tiles that can't fit anywhere are faded.
      color = selected ? COLORS[:selected] : TILE_COLORS[tile.value]
      alpha = if selected && state.dragging    then ALPHA[:picked_up]
              elsif board.fits_anywhere?(tile) then ALPHA[:opaque]
              else                                  ALPHA[:unusable]
              end

      # Center the tile in its rectangle.
      left = rect.x + (rect.w - tile.width * OPTION_CELL) / 2
      top  = rect.y + (rect.h + tile.height * OPTION_CELL) / 2
      tile.cells.each do |r, c|
        square x: left + c * OPTION_CELL, y: top - (r + 1) * OPTION_CELL,
               size: OPTION_CELL_INNER, color: color, alpha: alpha, corner: OPTION_CORNER
      end
    end
  end

  # While dragging, the tile follows the mouse with its anchor square under the
  # pointer (GameWindow#draw_dragged_tile). Over the board the preview shows
  # instead, snapped to the squares.
  def render_dragged_tile
    tile = selected_tile
    return unless state.dragging && tile
    return if cell_under_mouse

    mouse = inputs.mouse
    tile.cells.each do |r, c|
      square x: mouse.x - CELL_INNER / 2 + (c - tile.anchor) * CELL,
             y: mouse.y - CELL_INNER / 2 - r * CELL,
             size: CELL_INNER, color: TILE_COLORS[tile.value], alpha: ALPHA[:dragged]
    end
  end

  def render_panel
    label PANEL_CENTER_X, PANEL_Y[:title], "1010!", size: 64, color: :text, anchor_x: 0.5
    label PANEL_X, PANEL_Y[:score], "Score: #{state.board.score}", size: 40, color: :score
    label PANEL_X, PANEL_Y[:time], "Time: #{format_time play_seconds}", size: 24, color: :dim_text

    if game_over?
      hint = state.auto ? "Starting another game..." : "N: new game   U: undo"
      label PANEL_X, PANEL_Y[:status], "Game over!", size: 34, color: :score
      label PANEL_X, PANEL_Y[:status_hint], hint, size: 20, color: :text
    end

    if state.playback
      label PANEL_X, PANEL_Y[:mode], "PLAYBACK", size: 22, color: :hint
    elsif state.auto
      label PANEL_X, PANEL_Y[:mode], "AUTO: #{state.auto_player.strategy}", size: 22, color: :hint
      label PANEL_X, PANEL_Y[:mode_detail], "runs #{state.auto_runs}, best #{state.auto_best}",
            size: 22, color: :hint
    end

    HELP_LINES.each_with_index do |text, i|
      label PANEL_X, PANEL_Y[:help] - i * HELP_LINE_HEIGHT, text, size: 20, color: :dim_text
    end

    label MESSAGE_X, MESSAGE_Y, state.message.text, size: 20, color: :text if state.message
  end

  # A blinking red square and "REC" next to the time while a game is being
  # recorded (the original drew a blinking triangle).
  def render_recording_mark
    return unless state.recording

    y = PANEL_Y[:time]
    if Kernel.tick_count.idiv(BLINK_TICKS).even?
      outputs.sprites << { x: RECORDING_MARK_X, y: y - RECORDING_MARK / 2, w: RECORDING_MARK, h: RECORDING_MARK,
                           path: :solid }.merge(COLORS[:score])
    end
    label RECORDING_MARK_X + RECORDING_MARK + 6, y, "REC", size: 24, color: :score
  end

  # -------------------------------------------------------------------------
  # Drawing helpers
  # -------------------------------------------------------------------------

  # A square with clipped corners, like GameWindow#draw_sqr. Built from three
  # rectangles that don't overlap, so it also looks right when see-through:
  #
  #    .######.
  #    ########
  #    ########
  #    .######.
  def square x:, y:, size:, color:, alpha: ALPHA[:opaque], corner: CORNER
    outputs.sprites << [
      { x: x + corner,        y: y,          w: size - 2 * corner, h: size },
      { x: x,                 y: y + corner, w: corner,            h: size - 2 * corner },
      { x: x + size - corner, y: y + corner, w: corner,            h: size - 2 * corner }
    ].map { |rect| rect.merge(path: :solid, a: alpha).merge(color) }
  end

  def board_square row, col, color, alpha: ALPHA[:opaque]
    x, y = cell_xy row, col
    square x: x, y: y, size: CELL_INNER, color: color, alpha: alpha
  end

  # Like board_square for a list of [row, col], skipping any off the board.
  #
  # NOTE: the parentheses matter. Without them, DragonRuby reads the line
  # after a trailing `alpha:` as alpha's default value, not as the method body.
  def board_squares(cells, color, alpha:)
    cells.each do |row, col|
      next unless state.board.inside?(row, col)
      board_square row, col, color, alpha: alpha
    end
  end

  # `color` is a key of COLORS, e.g. :score.
  def label x, y, text, size:, color:, anchor_x: 0
    outputs.labels << { x: x, y: y, text: text, size_px: size,
                        anchor_x: anchor_x, anchor_y: 0.5 }.merge(COLORS[color])
  end

  # Since the game opened, like the original: in auto mode that covers every
  # game played, not just the one in progress.
  def play_seconds
    (Kernel.tick_count - state.opened_at).idiv(60)  # 60 ticks per second
  end

  def format_time seconds
    "#{seconds.idiv(60)}:#{(seconds % 60).to_s.rjust(2, '0')}"
  end
end

# ---------------------------------------------------------------------------
# DragonRuby entry points
# ---------------------------------------------------------------------------

def boot args
  args.state = {}
end

def tick args
  $game ||= Game.new
  $game.args = args
  $game.tick
end

# DR.reset (from the console) clears args.state; forget the Game too.
def reset args
  $game = nil
end

# Called once before the game exits, however it is closed.
def shutdown args
  $game.print_summary if $game
end
