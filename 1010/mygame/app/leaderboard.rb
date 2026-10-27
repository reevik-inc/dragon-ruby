# The best scores of games you played yourself (H shows them). Games the
# computer played in auto mode don't count; the panel shows their best
# separately.
#
# Like Board, this only keeps the scores. Game reads and writes the file
# (data/1010scores.txt), one score per line, best first:
#   1234 2026-10-27
class Leaderboard
  SIZE = 10  # scores kept

  # Each entry is { score:, date: }, best first.
  attr_reader :entries

  def initialize entries = []
    @entries = entries
  end

  def best
    @entries.empty? ? 0 : @entries.first.score
  end

  # Adds a score and returns its entry, or nil if it isn't good enough to be
  # kept. Pass `replacing:` the entry this game added before (a game can end
  # again after an undo): the better of the two is kept.
  #
  # NOTE: entries are compared with equal?, since two games can end with the
  # same score on the same day.
  def add score, date, replacing: nil
    return replacing if replacing && score <= replacing.score

    @entries = @entries.reject { |e| e.equal?(replacing) }
    entry = { score: score, date: date }
    @entries = (@entries + [entry]).sort_by { |e| -e.score }.first(SIZE)
    rank(entry) ? entry : nil
  end

  # 1 for the best score, or nil if the entry isn't on the board.
  def rank entry
    index = @entries.find_index { |e| e.equal?(entry) }
    index && index + 1
  end

  def to_text
    @entries.map { |e| "#{e.score} #{e.date}\n" }.join
  end

  # Builds a Leaderboard from text made by to_text. Lines that don't look
  # like "<score> <date>" are left out, and returned as `problems` so the
  # game can report them: [leaderboard, problems].
  def self.from_text text
    entries  = []
    problems = []
    text.split("\n").each_with_index do |line, i|
      next if line.strip.empty?

      score, date = line.strip.split(" ", 2)
      if Board.digits?(score.to_s, Board::DIGITS) && date
        entries << { score: score.to_i, date: date }
      else
        problems << "line #{i + 1} is not a score: #{line.inspect}"
      end
    end
    [Leaderboard.new(entries.sort_by { |e| -e.score }.first(SIZE)), problems]
  end
end
