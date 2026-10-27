# 1010!: a DragonRuby port of the Gosu game at https://github.com/shanko/1010
#
# The game is split into these files (with what they replace in the Gosu version):
#   app/tiles.rb           the 19 tile shapes                 (Board1010::ALL_TILES)
#   app/board.rb           the rules, no drawing at all       (Board1010)
#   app/auto_player.rb     how the computer picks its moves   (AutoPlayer)
#   app/move_animation.rb  shows a move square by square      (MoveAnimation)
#   app/leaderboard.rb     your best scores (H shows them)    (new)
#   app/game_log.rb        reports what happens, and errors   (puts)
#   app/main.rb            input, auto play and drawing       (GameWindow)
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
#
# What happens in a session (its seed, each game's score, saves, warnings and
# errors) is printed to the console and written to data/1010.log; see
# game_log.rb.

require "app/game_log.rb"
require "app/tiles.rb"
require "app/board.rb"
require "app/auto_player.rb"
require "app/leaderboard.rb"
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

# The panel on the right: score, status, and the help or the high scores.
PANEL_X        = 990
PANEL_W        = 240
PANEL_CENTER_X = PANEL_X + PANEL_W.idiv(2)
PANEL_Y = {
  title:       660,
  score:       595,
  best:        558,
  time:        528,
  undos:       496,  # a heart per undo left
  skips:       468,
  status:      436,
  status_hint: 408,
  mode:        380,  # AUTO or PLAYBACK
  mode_detail: 356,
  help:        322   # or the high scores (H)
}
HELP_LINE_HEIGHT = 23
RECORDING_MARK_X = PANEL_X + 150  # next to the time
RECORDING_MARK   = 16

# The undo hearts. A Tile only for its shape: '#' is a filled pixel.
HEART = Tile.new(:heart, 0, [".##.##.",
                             "#######",
                             "#######",
                             ".#####.",
                             "..###..",
                             "...#..."])
HEART_PIXEL = 3                                   # size of one '#'
HEART_STEP  = (HEART.width + 2) * HEART_PIXEL     # from one heart to the next

# The high scores (H) replace the help: rank, score (right-aligned) and date.
SCORE_COLUMNS = { rank: PANEL_X, score: PANEL_X + 95, date: PANEL_X + 110 }

# Messages like "Game saved" go below the board, where long ones fit.
MESSAGE_X = BOARD_X
MESSAGE_Y = 28

HELP_LINES = [
  "Drag a tile onto the board,",
  "or pick one (click or 1/2/3)",
  "then click a square.",
  "Right click: drop selection",
  "O (hold): best spot for tile",
  "U: undo    D: new tiles",
  "N: new game  H: high scores",
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
  c:      :print_positions,
  h:      :toggle_scores
}

# Keys that make moves, ignored while the computer or a playback is playing.
PLAYER_ACTIONS = {
  e: :auto_move,  # let the computer make one move
  u: :undo,
  d: :skip_tiles  # deal a new set of tiles
}

OPTION_KEYS = { one: 0, two: 1, three: 2 }

# ---------------------------------------------------------------------------
# Timing and files
# ---------------------------------------------------------------------------

AUTO_DELAY    = 8    # ticks between computer (and playback) moves, after the animation
AUTO_RESTART  = 90   # ticks to show "Game over" before auto mode starts again
MESSAGE_TICKS = 120  # how long messages like "Game saved" stay up
BLINK_TICKS   = 15   # how fast the recording mark blinks

SAVE_FILE   = "data/1010game.txt"  # relative to the mygame folder
SCORES_FILE = "data/1010scores.txt"
LOG_FILE    = "data/1010.log"

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
  dim_text:        { r: 120, g: 120, b: 130 },
  warning:         { r: 205, g: 110, b: 0   },
  heart:           { r: 225, g: 35,  b: 70  },
  used_heart:      { r: 215, g: 215, b: 215 }
}

# The color of a message below the board, by its level (see show_message).
MESSAGE_COLORS = { info: :text, warn: :warning, error: :invalid }

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
    state.session_seed   = options[:seed] || rand(2**31)
    state.seeds          = Random.new(state.session_seed)
    state.auto_player    = auto_player_for options[:strategy]
    state.auto           = options[:auto]  # computer plays (A)
    state.auto_runs      = 0               # games finished in auto mode
    state.auto_best      = 0               # best auto score so far
    state.recording      = nil             # { seed:, events: } of the game being recorded
    state.last_recording = nil
    state.playback       = nil             # events still to replay
    state.opened_at      = Kernel.tick_count  # for the time played, over every game
    state.show_scores    = false           # H: high scores instead of the help

    # Tests pass their own files; a nil scores file keeps the scores in memory.
    state.save_file      = options.fetch(:save_file, SAVE_FILE)
    state.scores_file    = options.fetch(:scores_file, SCORES_FILE)

    GameLog.info "Session seed #{state.session_seed} (start with --seed #{state.session_seed} to repeat it)"
    options.fetch(:warnings, []).each { |warning| show_message warning, level: :warn }
    load_scores

    # Like the original, carry on with a saved game if there is one.
    load_game quiet: true unless state.auto
    new_game unless state.board
  end

  # Reads `--auto [strategy] --seed N` from the command line.
  # (DragonRuby gives a bare `--auto` the value nil.) Problems are returned
  # as `warnings:` for setup to show, since the game hasn't started yet.
  def self.options_from cli
    options = { auto: cli.key?(:auto), strategy: cli[:auto] || AutoPlayer::DEFAULT_STRATEGY }
    return options unless cli.key?(:seed)

    seed = cli[:seed].to_s
    if Board.digits?(seed, Board::DIGITS)
      options[:seed] = seed.to_i
    else
      options[:warnings] = ["--seed needs a whole number, not #{seed.inspect}: using a random seed"]
    end
    options
  end

  # Falls back to the default strategy (with a message) if `strategy` is unknown.
  def auto_player_for strategy
    unless AutoPlayer::STRATEGIES.include?(strategy.to_sym)
      GameLog.info "The strategies are: #{AutoPlayer::STRATEGIES.join(', ')}"
      show_message "Unknown strategy #{strategy}, using #{AutoPlayer::DEFAULT_STRATEGY}", level: :warn
      strategy = AutoPlayer::DEFAULT_STRATEGY
    end
    AutoPlayer.new strategy, random: Random.new(next_seed)
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
    state.history         = []     # the boards before the last few moves, for undo
    state.score_entry     = nil    # this game's place in the high scores, once it ends
    state.selected_option = nil    # index of the chosen tile in board.options
    state.dragging        = false  # is the chosen tile being dragged?
    state.animation       = nil    # the MoveAnimation of the last move
    state.playback        = nil    # a new game also ends a playback
    state.next_auto_at    = Kernel.tick_count
    # A loaded game may have ended already: that isn't a new result to record.
    state.game_over       = board.game_over?
    state.ended_at        = state.game_over ? Kernel.tick_count : nil
  end

  # Call after every change to the board. (Checking every frame would mean
  # trying every tile on every square 60 times a second.)
  def refresh_game_over
    was_over        = state.game_over
    state.game_over = state.board.game_over?
    state.ended_at  = state.game_over ? (state.ended_at || Kernel.tick_count) : nil
    return unless state.game_over && !was_over

    GameLog.info "Game over with a score of #{state.board.score}"
    record_score unless computer_playing?
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
  rescue => e
    log_crash e
    raise  # DragonRuby then shows the error and writes logs/exceptions/
  end

  # Logs what is needed to repeat a crash: the seeds, the mode and the board.
  # DragonRuby retries the tick, so the same error is only logged once.
  def log_crash error
    return if @last_crash == error.message

    @last_crash = error.message
    board = state.board
    GameLog.error "#{error.class}: #{error.message}"
    GameLog.error "  at #{(error.backtrace || []).first(5).join("\n     ")}"
    GameLog.error "  session seed #{state.session_seed}, game seed #{state.seed.inspect}, " \
                  "auto #{state.auto.inspect}, playback #{!state.playback.nil?}"
    GameLog.error "  board:\n#{board.to_save}" if board
  end

  def game_over?
    state.game_over
  end

  def selected_tile
    state.selected_option && state.board.options[state.selected_option]
  end

  # While the computer or a playback is playing, the player's moves would
  # interfere, so the keys and mouse that make moves are ignored.
  def computer_playing?
    state.auto || state.playback
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
    state.animation = nil if state.animation&.done?(now)
    state.message   = nil if state.message && now - state.message.at >= MESSAGE_TICKS
  end

  # -------------------------------------------------------------------------
  # Input
  # -------------------------------------------------------------------------

  # Looks each key pressed this frame up in KEY_ACTIONS, PLAYER_ACTIONS and
  # OPTION_KEYS. (key_down is true only on the frame a key is pressed.)
  def handle_keyboard
    keys = inputs.keyboard.key_down

    KEY_ACTIONS.each { |key, action| send action if keys.send(key) }
    return if computer_playing?

    PLAYER_ACTIONS.each { |key, action| send action if keys.send(key) }
    OPTION_KEYS.each { |key, index| select_option index if keys.send(key) }
  end

  # Two ways to place a tile, as in the original:
  #   - drag it from the options and let go over the board, or
  #   - click it (or press 1/2/3), then click a square on the board.
  # Either way the tile is placed when the mouse button is RELEASED over the board.
  def handle_mouse
    mouse = inputs.mouse
    return if computer_playing? || game_over?

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
      GameLog.info "Option #{index + 1} #{tile.name} fits first at #{state.board.find_position(tile).inspect}"
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

    remember_for_undo before
    state.recording.events << [:move, index, row, col] if state.recording
    state.selected_option = nil
    clear_step = state.auto ? MoveAnimation::PLACE_STEP_TICKS : MoveAnimation::CLEAR_STEP_TICKS
    state.animation = MoveAnimation.new move, Kernel.tick_count, clear_step: clear_step
    refresh_game_over
    true
  end

  # Keeps the board from before a move, as far back as there are undos left.
  def remember_for_undo board
    state.history << board
    state.history.shift while state.history.length > Board::UNDOS
  end

  # Goes back one move, Board::UNDOS times per game (shown as hearts).
  # Returns false if it can't.
  def undo
    board = state.board
    return refuse("No undos left in this game") if board.undos_left == 0
    return refuse("Nothing to undo") if state.history.empty?

    state.board            = state.history.pop
    state.board.undos_left = board.undos_left - 1  # the older board had more
    state.selected_option  = nil
    state.animation       = nil
    state.recording.events << [:undo] if state.recording
    refresh_game_over
    true
  end

  # D: swaps the tiles on offer for a new set, Board::SKIPS times per game.
  # Like a move, it can be undone.
  def skip_tiles
    before = state.board.copy
    return refuse("No new tiles left in this game") unless state.board.skip_options

    remember_for_undo before
    state.recording.events << [:skip] if state.recording
    state.selected_option = nil
    refresh_game_over
    true
  end

  # Shows why something can't be done, and returns false.
  def refuse text
    show_message text
    false
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
      GameLog.info "Score = #{state.auto_best}, a new best after #{state.auto_runs} games"
    end
    new_game
  end

  # The strategy is in auto_player.rb (jc unless --auto names another).
  # A move that doesn't fit is a bug in the strategy, so auto mode stops
  # instead of trying it again and again.
  def auto_move
    move = state.auto_player.choose_move state.board
    return if move.nil? && game_over?
    return if move && try_place(*move)

    state.auto = false
    show_message "Bug: the #{state.auto_player.strategy} player chose #{move.inspect}, " \
                 "which doesn't fit. Auto mode is off.", level: :error
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

  # Stops with an error if an event can't be replayed, which means the
  # recording doesn't match the game it is replayed on.
  def play_back_next
    event = state.playback.shift
    kind, *move = event  # [:move, index, row, col], [:undo], [:skip] or nil at the end
    replayed = case kind
               when :move then try_place(*move)
               when :undo then undo
               when :skip then skip_tiles
               when nil   then finish_playback
               end
    unless replayed
      state.playback = nil
      show_message "Playback stopped: #{event.inspect} doesn't work on this board", level: :error
    end
    state.next_auto_at = Kernel.tick_count + AUTO_DELAY
  end

  def finish_playback
    state.playback = nil
    show_message "Playback finished"
    true
  end

  # -------------------------------------------------------------------------
  # Saving and quitting
  # -------------------------------------------------------------------------

  # Returns false if the game couldn't be saved.
  def save_game
    DR.write_file state.save_file, state.board.to_save
    show_message "Game saved (score #{state.board.score})"
    true
  rescue => e
    show_error "Couldn't save the game to #{state.save_file}", e
    false
  end

  def load_game quiet: false
    text = begin
      DR.read_file state.save_file  # nil if there is no save file
    rescue => e
      return show_error("Couldn't read #{state.save_file}", e)
    end
    if text.nil?
      show_message "No saved game" unless quiet
      return
    end

    board = Board.from_save text, random: Random.new(next_seed)
    board.deal_if_needed
    start board
    show_message "Loaded the saved game, score #{board.score} (N starts a new one)"
  rescue Board::DamagedSave => e
    show_message "The save file is damaged: #{e.message}", level: :error
  end

  # Shows `text` below the board for a while, and logs it. Warnings and
  # errors are drawn in color (MESSAGE_COLORS).
  def show_message(text, level: :info)
    GameLog.write level, text
    state.message = { text: text, level: level, at: Kernel.tick_count }
    nil
  end

  # For something that failed: shows `text`, and logs the exception too.
  def show_error text, exception
    show_message "#{text} (see #{LOG_FILE})", level: :error
    GameLog.error "#{exception.class}: #{exception.message.strip}"
    nil
  end

  # Doesn't quit if the save failed, so the game isn't lost.
  def save_and_quit
    DR.request_quit if save_game
  end

  # -------------------------------------------------------------------------
  # High scores (see leaderboard.rb)
  # -------------------------------------------------------------------------

  # Lines of the scores file that can't be read are reported and left out.
  def load_scores
    text = state.scores_file && DR.read_file(state.scores_file)
    state.leaderboard, problems = Leaderboard.from_text(text.to_s)
    problems.each { |problem| GameLog.warn "#{state.scores_file}: #{problem}" }
  rescue => e
    state.leaderboard = Leaderboard.new
    show_error "Couldn't read the high scores from #{state.scores_file}", e
  end

  # When a game you played ends. If you undo and it ends again, the better
  # of the two scores is kept.
  def record_score
    leaderboard = state.leaderboard
    best_before = leaderboard.best
    score       = state.board.score
    state.score_entry = leaderboard.add score, GameLog.timestamp.split(" ").first, replacing: state.score_entry
    return unless state.score_entry

    if score > best_before
      show_message "New high score: #{score}!"
    else
      GameLog.info "Score #{score} is number #{leaderboard.rank(state.score_entry)} in the high scores"
    end
    save_scores
  end

  def save_scores
    DR.write_file state.scores_file, state.leaderboard.to_text if state.scores_file
  rescue => e
    show_error "Couldn't save the high scores to #{state.scores_file}", e
  end

  # H: the panel shows the high scores instead of the help, and back.
  def toggle_scores
    state.show_scores = !state.show_scores
  end

  # Esc: deletes the saved game too, so the next start is a new game.
  def quit_without_saving
    delete_save
    DR.request_quit
  end

  def delete_save
    return unless DR.stat_file(state.save_file)

    DR.delete_file state.save_file
    GameLog.info "Deleted the saved game"
  rescue => e
    show_error "Couldn't delete #{state.save_file}", e
  end

  # Called by `shutdown` when the game exits (Esc, Q or closing the window),
  # like GameWindow#close.
  def print_summary
    return unless state.board

    GameLog.info "Total time played = #{play_seconds} seconds"
    GameLog.info "Score = #{state.board.score}"
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
    solid_rect({ x: BOARD_X - BOARD_FRAME,
                 y: BOARD_TOP - BOARD_SIZE - BOARD_FRAME,
                 w: BOARD_SIZE + 2 * BOARD_FRAME,
                 h: BOARD_SIZE + 2 * BOARD_FRAME },
               COLORS[:board])

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
      fits  = board.fits?(tile, row, col)
      color = fits ? TILE_COLORS[tile.value] : COLORS[:invalid]
      board_squares board.cells_for(tile, row, col), color, alpha: fits ? ALPHA[:preview] : ALPHA[:blocked]
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

      solid_rect rect, selected ? COLORS[:option_selected] : COLORS[:option]
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
    panel_label :score, "Score: #{state.board.score}", size: 40, color: :score
    panel_label :best, "Your best: #{state.leaderboard.best}", size: 22, color: :text
    panel_label :time, "Time: #{format_time play_seconds}", size: 22, color: :dim_text
    render_undo_hearts
    panel_label :skips, "New tiles left (D): #{state.board.skips_left}", size: 18, color: :dim_text

    if game_over?
      hint = state.auto ? "Starting another game..." : game_over_hint
      panel_label :status, "Game over!", size: 30, color: :score
      panel_label :status_hint, hint, size: 18, color: :text
    end

    if state.playback
      panel_label :mode, "PLAYBACK", size: 22, color: :hint
    elsif state.auto
      panel_label :mode, "AUTO: #{state.auto_player.strategy}", size: 22, color: :hint
      panel_label :mode_detail, "runs #{state.auto_runs}, best #{state.auto_best}", size: 22, color: :hint
    end

    state.show_scores ? render_scores : render_help

    message = state.message
    label MESSAGE_X, MESSAGE_Y, message.text, size: 20, color: MESSAGE_COLORS[message.level] if message
  end

  # What can still be done when the game is over.
  def game_over_hint
    keys = ["N: new"]
    keys << "U: undo"      if state.board.undos_left > 0 && !state.history.empty?
    keys << "D: new tiles" if state.board.skips_left > 0
    keys.join("  ")
  end

  # A heart per undo: red while it can still be used, gray once used.
  def render_undo_hearts
    y = PANEL_Y[:undos]
    Board::UNDOS.times do |i|
      color = i < state.board.undos_left ? COLORS[:heart] : COLORS[:used_heart]
      pixel_icon HEART, PANEL_X + i * HEART_STEP, y, color
    end
    label PANEL_X + Board::UNDOS * HEART_STEP + 4, y, "undos (U)", size: 18, color: :dim_text
  end

  def render_help
    HELP_LINES.each_with_index do |text, i|
      label PANEL_X, help_line_y(i), text, size: 18, color: :dim_text
    end
  end

  # Your best scores, with this game's (once it has ended) highlighted.
  def render_scores
    label PANEL_X, help_line_y(0), "High scores (H: help)", size: 20, color: :text
    entries = state.leaderboard.entries
    label PANEL_X, help_line_y(1), "None yet: finish a game!", size: 18, color: :dim_text if entries.empty?

    entries.each_with_index do |entry, i|
      y     = help_line_y(i + 1)
      color = entry.equal?(state.score_entry) ? :score : :dim_text
      label SCORE_COLUMNS[:rank],  y, "#{i + 1}.",       size: 18, color: color
      label SCORE_COLUMNS[:score], y, entry.score.to_s, size: 18, color: color, anchor_x: 1
      label SCORE_COLUMNS[:date],  y, entry.date,       size: 18, color: color
    end
  end

  def help_line_y line
    PANEL_Y[:help] - line * HELP_LINE_HEIGHT
  end

  # A blinking red square and "REC" next to the time while a game is being
  # recorded (the original drew a blinking triangle).
  def render_recording_mark
    return unless state.recording

    y = PANEL_Y[:time]
    if Kernel.tick_count.idiv(BLINK_TICKS).even?
      solid_rect({ x: RECORDING_MARK_X, y: y - RECORDING_MARK.idiv(2), w: RECORDING_MARK, h: RECORDING_MARK },
                 COLORS[:score])
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
    [
      { x: x + corner,        y: y,          w: size - 2 * corner, h: size },
      { x: x,                 y: y + corner, w: corner,            h: size - 2 * corner },
      { x: x + size - corner, y: y + corner, w: corner,            h: size - 2 * corner }
    ].each { |rect| solid_rect rect, color, alpha: alpha }
  end

  # A plain filled rectangle. `rect` is { x:, y:, w:, h: } and `color` a
  # value of COLORS or TILE_COLORS.
  def solid_rect(rect, color, alpha: ALPHA[:opaque])
    outputs.sprites << rect.merge(path: :solid, a: alpha).merge(color)
  end

  # Draws `shape` (a Tile) pixel by pixel, its left edge at x and centered on y.
  def pixel_icon shape, x, y, color, pixel: HEART_PIXEL
    top = y + shape.height * pixel / 2
    shape.cells.each do |r, c|
      solid_rect({ x: x + c * pixel, y: top - (r + 1) * pixel, w: pixel, h: pixel }, color)
    end
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

  # A label on one of the panel's rows (a key of PANEL_Y).
  def panel_label(row, text, size:, color:)
    label PANEL_X, PANEL_Y[row], text, size: size, color: color
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
  GameLog.open LOG_FILE unless GTK.cli_arguments.key?(:test)  # tests don't touch it
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
