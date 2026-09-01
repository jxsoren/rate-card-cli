# frozen_string_literal: true

module RateCard
  module TUI
    module Fields
      # Pick exactly one. Bubbles::List would do this, but it brings a title
      # bar, pagination and a filter this wizard has no use for, and it cannot
      # be shared with MultiSelect below — so both are built on one small
      # cursor-and-window core instead.
      class Select
        WINDOW = 8

        attr_reader :label

        # choices: Array<[display String, value]>
        def initialize(label:, choices:)
          @label = label
          @choices = choices
          @cursor = 0
          @value = nil
          @chosen = false
        end

        def done? = @chosen
        def value = @value

        def update(message)
          return nil unless message.is_a?(Bubbletea::KeyMessage)

          if message.up? || message.to_s == 'k'
            move(-1)
          elsif message.down? || message.to_s == 'j'
            move(1)
          elsif message.enter?
            @value = @choices[@cursor].last
            @chosen = true
          end
          nil
        end

        def view
          lines = ["#{Theme.accent(Theme::CURSOR)} #{Theme.bold(@label)}"]
          window.each do |index|
            display = @choices[index].first
            lines << if index == @cursor
                       "  #{Theme.accent(Theme::CURSOR)} #{Theme.accent(display)}"
                     else
                       "    #{display}"
                     end
          end
          lines << "  #{Theme.muted(overflow_hint)}" if overflow_hint
          lines.join("\n")
        end

        private

        def move(delta)
          @cursor = (@cursor + delta) % @choices.length
        end

        # Keeps the cursor inside a fixed-height window so a long service list
        # does not push the banner and earlier answers off the screen.
        def window
          return (0...@choices.length) if @choices.length <= WINDOW

          start = [[@cursor - (WINDOW / 2), 0].max, @choices.length - WINDOW].min
          (start...(start + WINDOW))
        end

        def overflow_hint
          return nil if @choices.length <= WINDOW

          "#{@cursor + 1}/#{@choices.length}"
        end
      end
    end
  end
end
