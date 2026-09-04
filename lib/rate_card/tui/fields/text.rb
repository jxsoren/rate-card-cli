# frozen_string_literal: true

require 'bubbles'

module RateCard
  module TUI
    module Fields
      # A single-line answer, optionally masked and optionally validated.
      #
      # Validation runs on Enter and keeps the field open on failure, so a
      # mistyped zone list or a mangled paste of a JWT costs a keystroke rather
      # than the run — the same guarantee the tty-prompt wizard made.
      class Text
        HELP_BINDINGS = [
          Bubbles::Key.binding(keys: ['enter'], help: ['enter', 'confirm']),
          Bubbles::Key.binding(keys: ['esc'], help: ['esc', 'back'])
        ].freeze

        attr_reader :label, :error

        # parse: String -> value, raising ArgumentError with a message to show.
        def initialize(label:, parse:, default: nil, mask: false, hint: nil)
          @label = label
          @parse = parse
          @default = default
          @hint = hint
          @error = nil
          @value = nil

          @input = Bubbles::TextInput.new
          @input.prompt = ''
          @input.placeholder = default.to_s if default
          if mask
            @input.echo_mode = :password
            @input.echo_character = '•'
          end
          @input.focus
        end

        def done? = !@value.nil?
        def value = @value

        # Pulled out of #view so App can draw it in a persistent footer bar
        # instead of repeating it under every single field.
        def keymap_hint = Theme.help_view(HELP_BINDINGS)

        def update(message)
          if message.is_a?(Bubbletea::KeyMessage) && message.enter?
            submit
            return nil
          end

          @input, command = @input.update(message)
          command
        end

        def view
          lines = ["#{Theme.accent(Theme::CURSOR)} #{Theme.bold(@label)} #{@input.view}"]
          lines << "  #{Theme.muted(@hint)}" if @hint
          lines << "  #{Theme.danger(Theme::CROSS)} #{Theme.danger(@error)}" if @error
          lines.join("\n")
        end

        private

        # An empty answer means "take the default"; without this the placeholder
        # would be shown but never actually used.
        def submit
          raw = @input.value.to_s.strip
          raw = @default.to_s if raw.empty? && @default

          @value = @parse.call(raw)
          @error = nil
        rescue ArgumentError => e
          @error = e.message
          @value = nil
          @input.reset
        end
      end
    end
  end
end
