# frozen_string_literal: true

require 'pastel'
require 'tty-box'
require 'tty-progressbar'
require 'tty-spinner'

module RateCard
  # Everything this tool prints goes through here, so no other class touches
  # colour codes and specs can assert against a StringIO.
  class UI
    MAX_LISTED_FAILURES = 10
    MAX_LISTED_WARNINGS = 10

    def initialize(io: $stdout)
      @io = io
      @pastel = Pastel.new(enabled: io.respond_to?(:tty?) && io.tty?)
    end

    def banner
      @io.puts
      @io.puts TTY::Box.frame(
        'eHub Rate Card Builder',
        "#{@pastel.red('●')} production · api.ehub.com",
        padding: [0, 1],
        border: :thick
      )
    end

    # email is accepted and ignored so the caller can splat Token.decode directly.
    def customer_confirmed(name:, customer_id:, email: nil)
      @io.puts "  #{@pastel.green('✓')} #{@pastel.bold(name)} (customer_id #{customer_id})"
    end

    def info(message)
      @io.puts "#{@pastel.cyan('▸')} #{message}"
    end

    def warn(message)
      @io.puts "  #{@pastel.yellow('⚠')} #{message}"
    end

    def error(message)
      @io.puts "  #{@pastel.red('✗')} #{message}"
    end

    def success(message)
      @io.puts "  #{@pastel.green('✓')} #{message}"
    end

    def blank
      @io.puts
    end

    # The last thing shown before the confirm, so it repeats every answer back:
    # eight prompts earlier the user cannot otherwise check what they chose, and
    # the alternative is confirming a slow production run on a bare number.
    def recap(spec)
      @io.puts
      @io.puts "  #{@pastel.bold(spec.carrier)} · #{spec.service_names.join(', ')}"
      @io.puts "  zones #{spec.zone_summary} · weights #{spec.weight_summary} · " \
               "#{spec.package_type}"
      @io.puts "  columns: #{spec.rate_key_labels.join(', ')}"
      @io.puts "  #{@pastel.bold(spec.call_count.to_s)} rate calls against production"
    end

    # Wraps a slow step with a spinner, returning the block's value.
    def with_spinner(message)
      spinner = TTY::Spinner.new("#{@pastel.cyan(':spinner')} #{message}", format: :dots,
                                                                          output: @io)
      spinner.auto_spin
      result = yield
      spinner.success(@pastel.green('✓'))
      result
    rescue StandardError
      spinner.error(@pastel.red('✗'))
      raise
    end

    # Yields a callable that advances the bar once per completed call.
    def with_progress(total)
      bar = TTY::ProgressBar.new(
        '  fetching [:bar] :current/:total · :elapsed elapsed',
        total: total, output: @io, bar_format: :block
      )
      # ensure, not a plain call after yield: a rejected token aborts the fetch
      # mid-bar, and without this the error prints under a half-drawn bar.
      yield(-> { bar.advance })
    ensure
      bar.finish
    end

    def print_tables(tables)
      tables.each do |title, rendered|
        @io.puts
        @io.puts "  #{@pastel.bold(title)}"
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
