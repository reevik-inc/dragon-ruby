# The 19 tile shapes of 1010!, ported from Board1010::ALL_TILES in the
# original Gosu version (board.rb).
#
# The original stored each shape as a matrix of numbers. Here each shape is
# drawn as text instead: '#' is a filled square and '.' an empty one, and the
# first string is the TOP row. The names follow the original constants:
#   HL = horizontal line, VL = vertical line, SQ = square,
#   BL / TL / BR / TR = the corner shapes.
class Tile
  # name:   e.g. :sq3 (used in save files)
  # value:  picks the color, and is what gets stored in the board's cells,
  #         like the numbers inside the original matrices
  # cells:  [row, col] of every filled square, relative to the top-left
  # anchor: column of the first filled square in the top row. The square you
  #         click on (or drop onto) is where the anchor goes, exactly like
  #         Board1010#place shifted the column left past leading zeros.
  attr_reader :name, :value, :cells, :width, :height, :anchor

  def initialize name, value, rows
    @name   = name
    @value  = value
    @width  = rows.map(&:length).max
    @height = rows.length
    @anchor = rows[0].index("#")

    @cells = []
    rows.each_with_index do |line, row|
      line.chars.each_with_index do |char, col|
        @cells << [row, col] if char == "#"
      end
    end
  end
end

ALL_TILES = [
  Tile.new(:dot, 1, ["#"]),

  Tile.new(:hl2, 2, ["##"]),
  Tile.new(:hl3, 3, ["###"]),
  Tile.new(:hl4, 4, ["####"]),
  Tile.new(:hl5, 5, ["#####"]),

  Tile.new(:vl2, 2, ["#", "#"]),
  Tile.new(:vl3, 3, ["#", "#", "#"]),
  Tile.new(:vl4, 4, ["#", "#", "#", "#"]),
  Tile.new(:vl5, 5, ["#", "#", "#", "#", "#"]),

  Tile.new(:sq2, 2, ["##",
                     "##"]),
  Tile.new(:sq3, 3, ["###",
                     "###",
                     "###"]),

  Tile.new(:bl2, 2, ["#.",
                     "##"]),
  Tile.new(:bl3, 3, ["#..",
                     "#..",
                     "###"]),

  Tile.new(:tl2, 2, ["##",
                     ".#"]),
  Tile.new(:tl3, 3, ["###",
                     "..#",
                     "..#"]),

  Tile.new(:br2, 2, [".#",
                     "##"]),
  Tile.new(:br3, 3, ["..#",
                     "..#",
                     "###"]),

  Tile.new(:tr2, 2, ["##",
                     "#."]),
  Tile.new(:tr3, 3, ["###",
                     "#..",
                     "#.."])
]

# Look up a tile by name (used when loading a saved game).
TILES_BY_NAME = ALL_TILES.map { |tile| [tile.name, tile] }.to_h

# When none of the 3 random tiles fit, the original swapped the first one for
# the first of these small tiles that does fit (Board1010#find_fitting_tile).
SMALL_TILES = [:hl2, :vl2, :sq2, :bl2, :tl2, :br2, :tr2, :dot].map { |name| TILES_BY_NAME[name] }
