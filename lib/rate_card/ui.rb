# frozen_string_literal: true

require_relative 'tui/theme'

module RateCard
  # Plain, non-interactive output: everything printed before the TUI starts or
  # after it exits — errors, the rate tables, the failure and warning reports,
  # and where the files went.
  #
  # The interactive half (banner, prompts, spinner, progress) moved to TUI::App
  # when this switched to Bubbletea. What stays here is deliberately dumb line
  # printing, so tables and reports survive being piped to a file and specs can
  # still assert against a StringIO.
  class UI
    MAX_LISTED_FAILURES = 10
    MAX_LISTED_WARNINGS = 10

    def initialize(io: $stdout)
      @io = io
    end

    # The one thing printed before the TUI starts, so the run says what it
    # targets before a production token is pasted into it.
    def banner
      @io.puts
      @io.puts TUI::Theme.banner
      @io.puts
    end

    # No newline: the answer is typed on the same line.
    def prompt(message)
      @io.print "#{TUI::Theme.accent(TUI::Theme::CURSOR)} #{TUI::Theme.bold(message)}"
      @io.flush
    end

    def info(message)
      @io.puts "#{TUI::Theme.accent(TUI::Theme::BULLET)} #{message}"
    end

    def warn(message)
      @io.puts "  #{TUI::Theme.warning(TUI::Theme::ALERT)} #{message}"
    end

    def error(message)
      @io.puts "  #{TUI::Theme.danger(TUI::Theme::CROSS)} #{message}"
    end

    def success(message)
      @io.puts "  #{TUI::Theme.ok(TUI::Theme::TICK)} #{message}"
    end

    def blank
      @io.puts
    end

    def print_tables(tables)
      tables.each do |title, rendered|
        @io.puts
        @io.puts "  #{TUI::Theme.bold(title)}"
        @io.puts rendered
      end
    end

    def failure_report(failures)
      return if failures.empty?

      @io.puts
      warn "#{failures.length} #{failures.length == 1 ? 'cell' : 'cells'} failed"
      failures.first(MAX_LISTED_FAILURES).each do |failure|
        @io.puts "      wt #{failure.weight}  Z#{failure.zone}  → #{failure.message}"
      end
      remaining = failures.length - MAX_LISTED_FAILURES
      @io.puts "      … and #{remaining} more" if remaining.positive?
    end

    # What the API itself reported on calls that succeeded. Separate from
    # #failure_report: those cells have no answer, these have an answer that
    # says why there is no rate.
    def warning_report(warnings)
      return if warnings.empty?

      @io.puts
      noun = warnings.length == 1 ? 'warning' : 'warnings'
      warn "the API reported #{warnings.length} #{noun}"
      warnings.first(MAX_LISTED_WARNINGS).each do |warning|
        repeat = warning.count > 1 ? " (×#{warning.count})" : ''
        @io.puts "      #{warning.message}#{repeat}"
      end
      remaining = warnings.length - MAX_LISTED_WARNINGS
      @io.puts "      … and #{remaining} more" if remaining.positive?
    end

    def saved(paths)
      return if paths.empty?

      @io.puts
      noun = paths.length == 1 ? 'file' : 'files'
      success "Saved #{paths.length} #{noun} to #{paths.first.dirname}"
      paths.each { |path| @io.puts "      #{path.basename}" }
    end
  end
end
