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

  # [row, col] steps to the 8 squares around a square.
  NEIGHBOUR_OFFSETS = [[-1, -1], [-1, 0], [-1, 1], [0, -1], [0, 1], [1, -1], [1, 0], [1, 1]]

  attr_reader :cells, :options, :score, :random

  # `random` deals the tiles. Pass Random.new(seed) to get the same tiles
  # every time (that is how a recorded game is played back).
  def initialize cells: nil, options: [], score: 0, random: Random.new
    @cells   = cells || Array.new(ROWS) { Array.new(COLS, EMPTY) }
    @options = options  # the tiles waiting to be placed (Board1010#options)
    @score   = score
    @random  = random
  end

  # A deep copy, used for undo. It shares the random number generator, so a
  # recorded game deals the same tiles when it is played back.
  def copy
    Board.new cells: @cells.map(&:dup), options: @options.dup, score: @score, random: @random
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
    inside?(row, col) && @cells[row][col] != EMPTY
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
    rows = (0...ROWS).select { |r| @cells[r].all? { |value| value != EMPTY } }
    cols = (0...COLS).select { |c| @cells.all? { |row| row[c] != EMPTY } }
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
    ROWS.times do |r|
      COLS.times do |c|
        return [r, c] if fits?(tile, r, c)
      end
    end
    nil
  end

  # Board1010#pos_exists? for a single tile. Stops at the first fit.
  def fits_anywhere? tile
    !find_position(tile).nil?
  end

  # Every [row, col] where the tile fits, top-left first
  # (Board1010#find_starting_pos).
  def positions_for tile
    positions = []
    ROWS.times do |r|
      COLS.times do |c|
        positions << [r, c] if fits?(tile, r, c)
      end
    end
    positions
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
  #   row=0000123000    (one line per row, top row first)
  def to_save
    lines = ["score=#{@score}", "options=#{@options.map(&:name).join(',')}"]
    @cells.each { |row| lines << "row=#{row.join}" }
    lines.join("\n")
  end

  # Builds a Board from text made by to_save, or returns nil if the text
  # doesn't look like a saved game.
  #
  # NOTE: DragonRuby has no Integer(text, exception: false) and no regular
  # expressions, so the score and rows are checked one character at a time.
  # A row may only hold the values tiles use (0 to 5), so a damaged file
  # can't crash the drawing.
  def self.from_save text, random: Random.new
    score   = nil
    options = []
    rows    = []

    text.split("\n").each do |line|
      key, value = line.strip.split("=", 2)
      value = value.to_s
      case key
      when "score"   then score = value.to_i if digits?(value, "0123456789")
      when "options" then options = value.split(",").map { |name| TILES_BY_NAME[name.to_sym] }.compact
      when "row"     then rows << (digits?(value, "012345") ? value.chars.map(&:to_i) : [])
      end
    end

    return nil if score.nil? || rows.length != ROWS || rows.any? { |row| row.length != COLS }

    Board.new cells: rows, options: options, score: score, random: random
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
