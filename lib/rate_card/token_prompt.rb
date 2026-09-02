# frozen_string_literal: true

require 'io/console'

module RateCard
  # Reads the API token before the TUI takes the terminal.
  #
  # This is deliberately NOT a TUI field. bubbletea-ruby's input reader returns
  # one key per poll and discards the rest of the buffered bytes, so a pasted
  # 200-character JWT arrives as a single character and the other 199 are lost
  # — verified against 0.1.4, and bracketed_paste does not help. Typing is
  # unaffected at any speed, so every other answer is safe inside the loop; the
  # token is the one field that is always pasted.
  #
  # Reading it here also means the terminal's own line editing handles the
  # paste, which is what makes it work.
  module TokenPrompt
    module_function

    # Returns the raw token, or nil if the user gave up (EOF / ctrl-d).
    def read(ui:, io: $stdin)
      loop do
        ui.prompt('eHub API token: ')
        raw = read_masked(io)
        return nil if raw.nil?

        raw = raw.strip
        # Never a silent `next`: that reprinted the prompt with no explanation,
        # and a pasted token whose clipboard content carries a leading newline
        # then reads as a doubled prompt or a hang. Not phrased as a bad token —
        # the user has not pasted one yet.
        if raw.empty?
          ui.error('no token on that line — paste the token')
          next
        end

        begin
          Providers::EHub::Token.decode(raw)
          return raw
        rescue Providers::EHub::Token::DecodeError => e
          ui.error("#{e.message} — paste the token again")
        end
      end
    end

    # noecho keeps the JWT off the screen; #gets keeps the terminal's line
    # discipline, which is what makes a paste arrive intact.
    def read_masked(io)
      if io.respond_to?(:noecho) && io.tty?
        value = io.noecho(&:gets)
        puts
        value
      else
        io.gets
      end
    end
  end
end
