# Shows a move step by step, after the board has already changed. Ported from
# move_animation.rb of the Gosu version.
#
# The original changed the board one square per frame and called sleep(0.25)
# between cleared lines, which froze the whole window. Here Board#play
# changes the board at once, and this class only says what each square should
# LOOK like at a given tick, so the game keeps drawing and reading input.
class MoveAnimation
  PLACE_STEP_TICKS = 1   # the tile's squares appear one per frame, like the original
  CLEAR_STEP_TICKS = 15  # then one row and one column empty every quarter second

  # `move` is a Move (see board.rb). `now` is Kernel.tick_count.
  def initialize move, now, clear_step: CLEAR_STEP_TICKS
    @cells_before_clearing = move.cells_before_clearing

    # {[row, col] => tick it appears}, one square per step.
    @appears_at = {}
    move.placed.each_with_index do |(row, col, _value), step|
      @appears_at[[row, col]] = now + step * PLACE_STEP_TICKS
    end

    # Then one cleared row and one cleared column empty per step.
    clearing_starts = now + move.placed.length * PLACE_STEP_TICKS
    @row_cleared_at = step_times move.cleared_rows, clearing_starts, clear_step
    @col_cleared_at = step_times move.cleared_cols, clearing_starts, clear_step
    steps    = [move.cleared_rows.length, move.cleared_cols.length].max
    @ends_at = clearing_starts + steps * clear_step
  end

  def done? now
    now >= @ends_at
  end

  # The value to draw for (row, col) at tick `now`, given its value on the board.
  def value_at row, col, board_value, now
    appears_at = @appears_at[[row, col]]
    return Board::EMPTY if appears_at && now < appears_at

    cleared_at = [@row_cleared_at[row], @col_cleared_at[col]].compact.min
    return @cells_before_clearing[row][col] if cleared_at && now < cleared_at

    board_value
  end

  private

  # {line => tick it empties}, one line per step.
  #
  # NOTE: each_with_index.to_h { ... } returns nils in DragonRuby, so the
  # Hash is filled in by hand.
  def step_times lines, start, step
    times = {}
    lines.each_with_index { |line, i| times[line] = start + i * step }
    times
  end
end
