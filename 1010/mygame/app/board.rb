# The rules of 1010!, ported from the Board1010 class (board.rb) of the
# original Gosu version.
#
# This file only knows about the game rules. It never calls DragonRuby APIs,
# so it is easy to unit test (see tests/board_tests.rb), and main.rb handles
# input and drawing.
#
# Like the original, rows are numbered from the TOP (row 0 is the top row)
# and an empty cell holds 0. A filled cell holds the value of the tile that
# filled it, which decides its color.
class Board
  ROWS    = 10
  COLS    = 10
  OPTIONS = 3   # tiles offered at a time
  EMPTY   = 0
  UNDOS   = 3   # undos allowed per game (the original allowed one at a time)
  SKIPS   = 3   # times per game the tiles on offer can be swapped for a new set

  # Every [row, col] on the board, top-left first, row by row.
  ALL_POSITIONS = (0...ROWS).to_a.product((0...COLS).to_a)

  # What a saved row may hold: an empty square or the value of some tile.
  SAVED_CELL_CHARS = ([EMPTY] + ALL_TILES.map(&:value)).uniq.join
  DIGITS           = "0123456789"

  # Raised by Board.from_save, with the reason the text isn't a saved game.
  class DamagedSave < StandardError; end

  # [row, col] steps to the 8 squares around a square.
  NEIGHBOUR_OFFSETS = [[-1, -1], [-1, 0], [-1, 1], [0, -1], [0, 1], [1, -1], [1, 0], [1, 1]]

  attr_reader :cells, :options, :score, :random, :skips_left
  attr_accessor :undos_left  # the game counts undos down (see Game#undo)

  # `random` deals the tiles. Pass Random.new(seed) to get the same tiles
  # every time (that is how a recorded game is played back).
  def initialize cells: nil, options: [], score: 0, random: Random.new, undos_left: UNDOS, skips_left: SKIPS
    @cells      = cells || Array.new(ROWS) { Array.new(COLS, EMPTY) }
    @options    = options  # the tiles waiting to be placed (Board1010#options)
    @score      = score
    @random     = random
    @undos_left = undos_left
    @skips_left = skips_left
  end

  # A deep copy, used for undo. It shares the random number generator, so a
  # recorded game deals the same tiles when it is played back.
  def copy
    Board.new cells: @cells.map(&:dup), options: @options.dup, score: @score, random: @random,
              undos_left: @undos_left, skips_left: @skips_left
  end

  # -------------------------------------------------------------------------
  # A move
  # -------------------------------------------------------------------------

  # One whole move: place option `index` with its anchor on (row, col),
  # remove it from the options, clear full lines and deal new tiles if all 3
  # are used up. Returns a Move (so the game can animate it), or nil if the
  # tile doesn't fit there.
  def play index, row, col
    tile = @options[index]
    return nil unless tile && fits?(tile, row, col)

    place tile, row, col
    @options.delete_at index
    cells_before_clearing = @cells.map(&:dup)
    rows, cols = full_lines
    clear_lines rows, cols
    deal_if_needed

    Move.new(placed: cells_for(tile, row, col).map { |r, c| [r, c, tile.value] },
             cells_before_clearing: cells_before_clearing,
             cleared_rows: rows,
             cleared_cols: cols)
  end

  # The game ends when none of the remaining tiles fit anywhere.
  def game_over?
    @options.none? { |tile| fits_anywhere?(tile) }
  end

  # -------------------------------------------------------------------------
  # Cells
  # -------------------------------------------------------------------------

  def inside? row, col
    row >= 0 && row < ROWS && col >= 0 && col < COLS
  end

  def empty? row, col
    inside?(row, col) && @cells[row][col] == EMPTY
  end

  def filled? row, col
    inside?(row, col) && !empty?(row, col)
  end

  # The board squares a tile would cover with its anchor on (row, col).
  def cells_for tile, row, col
    left = col - tile.anchor
    tile.cells.map { |r, c| [row + r, left + c] }
  end

  def fits? tile, row, col
    cells_for(tile, row, col).all? { |r, c| empty?(r, c) }
  end

  # Places the tile and returns the points earned (1 per square, as in the
  # original), or 0 if the tile doesn't fit there.
  def place tile, row, col
    return 0 unless fits?(tile, row, col)

    covered = cells_for(tile, row, col)
    covered.each { |r, c| @cells[r][c] = tile.value }
    @score += covered.length
    covered.length
  end

  # Rows and columns that have no empty squares left.
  # (Board1010#cleanup with dry_run = true)
  def full_lines
    rows = (0...ROWS).select { |r| (0...COLS).all? { |c| filled?(r, c) } }
    cols = (0...COLS).select { |c| (0...ROWS).all? { |r| filled?(r, c) } }
    [rows, cols]
  end

  # Empties the given rows and columns (Board1010#cleanup). All full lines are
  # found first and then cleared together, so a square where a full row
  # crosses a full column is handled correctly.
  def clear_lines rows, cols
    rows.each { |r| COLS.times { |c| @cells[r][c] = EMPTY } }
    cols.each { |c| ROWS.times { |r| @cells[r][c] = EMPTY } }
  end

  # -------------------------------------------------------------------------
  # The tiles on offer
  # -------------------------------------------------------------------------

  # Deals 3 new tiles once all of the current ones have been placed.
  def deal_if_needed
    @options = generate_options if @options.empty?
  end

  # Swaps the tiles on offer for a new set, SKIPS times per game. Returns
  # false when there are no skips left.
  def skip_options
    return false unless @skips_left > 0

    @skips_left -= 1
    @options = generate_options
    true
  end

  # Board1010#generate_tiles: 3 random tiles. If none of them fit anywhere,
  # the first one is swapped for a small tile that does fit.
  #
  # NOTE: DragonRuby's Array#sample doesn't take `random:`, so we pick an
  # index with our own random numbers instead.
  def generate_options
    tiles = Array.new(OPTIONS) { ALL_TILES[@random.rand(ALL_TILES.length)] }

    unless tiles.any? { |tile| fits_anywhere?(tile) }
      small = SMALL_TILES.find { |tile| fits_anywhere?(tile) }
      tiles[0] = small if small
    end

    tiles
  end

  # The first [row, col] where the tile fits, or nil.
  def find_position tile
    ALL_POSITIONS.find { |r, c| fits?(tile, r, c) }
  end

  # Board1010#pos_exists? for a single tile. Stops at the first fit.
  def fits_anywhere? tile
    !find_position(tile).nil?
  end

  # Every [row, col] where the tile fits, top-left first
  # (Board1010#find_starting_pos).
  def positions_for tile
    ALL_POSITIONS.select { |r, c| fits?(tile, r, c) }
  end

  # -------------------------------------------------------------------------
  # Measures used by the computer player (see auto_player.rb)
  # -------------------------------------------------------------------------

  # How many of the 8 squares around (row, col) are filled.
  def filled_neighbours row, col
    NEIGHBOUR_OFFSETS.count { |dr, dc| filled?(row + dr, col + dc) }
  end

  # 1 for touching the top or bottom edge, plus 1 for touching the left or
  # right edge.
  def edges_touched row, col
    count = 0
    count += 1 if row == 0 || row == ROWS - 1
    count += 1 if col == 0 || col == COLS - 1
    count
  end

  # How many rows and columns would be full after placing the tile there.
  def lines_completed_by tile, row, col
    trial = copy
    trial.place tile, row, col
    rows, cols = trial.full_lines
    rows.length + cols.length
  end

  # -------------------------------------------------------------------------
  # Saving
  # -------------------------------------------------------------------------

  # The original saved with Marshal (or a custom string under mruby).
  # This is a plain text format that is easy to read in an editor:
  #   score=133
  #   options=hl2,sq3,dot
  #   undos=2
  #   skips=3
  #   row=0000123000    (one line per row, top row first)
  def to_save
    lines = ["score=#{@score}", "options=#{@options.map(&:name).join(',')}",
             "undos=#{@undos_left}", "skips=#{@skips_left}"]
    @cells.each { |row| lines << "row=#{row.join}" }
    lines.join("\n")
  end

  # Builds a Board from text made by to_save. Raises DamagedSave, saying what
  # is wrong, if the text doesn't look like a saved game. Saves from before
  # undos and skips were counted get the full allowance.
  #
  # NOTE: DragonRuby has no Integer(text, exception: false) and no regular
  # expressions, so the score and rows are checked one character at a time.
  # A row may only hold the values tiles use, so a damaged file can't crash
  # the drawing.
  def self.from_save text, random: Random.new
    score   = nil
    options = []
    rows    = []
    undos   = UNDOS
    skips   = SKIPS

    text.split("\n").each_with_index do |line, i|
      line = line.strip
      next if line.empty?

      key, value = line.split("=", 2)
      value = value.to_s
      case key
      when "score" then score = whole_number(value, "the score")
      when "undos" then undos = whole_number(value, "undos", max: UNDOS)
      when "skips" then skips = whole_number(value, "skips", max: SKIPS)
      when "options"
        options = value.split(",").map do |name|
          TILES_BY_NAME[name.to_sym] || damaged!("there is no tile named #{name.inspect}")
        end
      when "row"
        unless value.length == COLS && digits?(value, SAVED_CELL_CHARS)
          damaged! "row #{rows.length + 1} is #{value.inspect}, not #{COLS} of the digits #{SAVED_CELL_CHARS}"
        end
        rows << value.chars.map(&:to_i)
      else
        damaged! "line #{i + 1} is not understood: #{line.inspect}"
      end
    end

    damaged! "the score is missing"                                    if score.nil?
    damaged! "it has #{rows.length} rows instead of #{ROWS}"           if rows.length != ROWS
    damaged! "it offers #{options.length} tiles, more than #{OPTIONS}" if options.length > OPTIONS

    Board.new cells: rows, options: options, score: score, random: random, undos_left: undos, skips_left: skips
  end

  def self.whole_number value, name, max: nil
    damaged! "#{name} #{value.inspect} is not a whole number" unless digits?(value, DIGITS)
    damaged! "#{name} #{value} is more than #{max}" if max && value.to_i > max
    value.to_i
  end

  def self.damaged! reason
    raise DamagedSave, reason
  end

  # Is `text` made only of the characters in `allowed` (and not empty)?
  def self.digits? text, allowed
    !text.empty? && text.chars.all? { |char| allowed.include?(char) }
  end
end

# What a move did, so the game can animate it (see move_animation.rb).
#   placed:                [row, col, value] of each square the tile filled
#   cells_before_clearing: the cells after placing the tile, before full lines were emptied
#   cleared_rows / cleared_cols: the full lines that were emptied
#
# NOTE: DragonRuby's Struct doesn't take `keyword_init: true`, so this is a
# small class instead.
class Move
  attr_reader :placed, :cells_before_clearing, :cleared_rows, :cleared_cols

  def initialize(placed:, cells_before_clearing:, cleared_rows:, cleared_cols:)
    @placed                = placed
    @cells_before_clearing = cells_before_clearing
    @cleared_rows          = cleared_rows
    @cleared_cols          = cleared_cols
  end
end
