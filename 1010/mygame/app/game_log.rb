# Everything worth knowing about a session goes through here: the seed it
# started with, each game's result, saves and loads, and every warning or
# error. Each line is
#   - printed with `puts`, so it shows in the console (` key), in the terminal
#     and in logs/puts.log,
#   - kept in memory (GameLog.entries), so tests can check what was reported,
#   - and, while the game runs (not under --test), appended with the date and
#     time to data/1010.log, which starts afresh each session.
#
# NOTE: DragonRuby's own GTK.log_warn and log_debug don't reach puts.log or
# logs/all.log, and log_info/log_error add their own prefix, so we use puts.
module GameLog
  LEVELS = { info: "INFO", warn: "WARN", error: "ERROR" }
  KEEP   = 200  # entries kept in memory

  # [level, text] of the latest entries, oldest first.
  def self.entries
    @entries ||= []
  end

  # How many entries were ever written (entries only keeps the last KEEP).
  def self.count
    @count ||= 0
  end

  # The [level, text] entries written since `count` was `start`.
  def self.since start
    entries.last([count - start, entries.length].min)
  end

  # Starts a new log file (or none, with nil).
  def self.open file
    @file = file
    DR.write_file @file, "" if @file
  rescue => e
    @file = nil
    puts "[1010] WARN: Can't write the log file #{file}: #{e.message}"
  end

  def self.info  text; write :info,  text; end
  def self.warn  text; write :warn,  text; end
  def self.error text; write :error, text; end

  def self.write level, text
    line = "[1010] #{LEVELS.fetch(level)}: #{text}"
    puts line
    entries << [level, text]
    entries.shift while entries.length > KEEP
    @count = count + 1
    append_to_file line
  end

  # A failing log file must never stop the game, so it is just switched off.
  def self.append_to_file line
    return unless @file

    DR.append_file @file, "#{timestamp} #{line}\n"
  rescue => e
    @file = nil
    puts "[1010] WARN: Stopped writing the log file: #{e.message}"
  end

  # "2026-10-27 15:10:35". NOTE: DragonRuby's Time has no strftime.
  def self.timestamp t = Time.now
    format "%04d-%02d-%02d %02d:%02d:%02d", t.year, t.month, t.day, t.hour, t.min, t.sec
  end
end
