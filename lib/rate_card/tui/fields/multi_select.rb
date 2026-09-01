# frozen_string_literal: true

require 'set'

module RateCard
  module TUI
    module Fields
      # Pick one or more. There is no multi-select in bubbles — List is
      # single-select — so this is the one widget the migration had to build,
      # and the wizard needs it twice (services, rate columns).
      #
      # Enter with nothing ticked is refused rather than accepted as "none":
      # every caller here has a min of 1, and a silent empty answer would fail
      # much later in RunSpec#validate!.
      class MultiSelect
        WINDOW = 8

        attr_reader :label, :error

        # choices: Array<[display String, value]>
        # checked: indexes ticked on entry.
        def initialize(label:, choices:, checked: [])
          @label = label
          @choices = choices
          @checked = checked.to_a.to_set
          @cursor = 0
          @error = nil
          @done = false
        end

        def done? = @done

        def value
          @choices.each_with_index
                  .select { |_choice, index| @checked.include?(index) }
                  .map { |choice, _index| choice.last }
        end

        def update(message)
          return nil unless message.is_a?(Bubbletea::KeyMessage)

          if message.up? || message.to_s == 'k'
            move(-1)
          elsif message.down? || message.to_s == 'j'
            move(1)
          elsif space?(message)
            toggle
          elsif message.to_s == 'a'
            toggle_all
          elsif message.enter?
            submit
          end
          nil
        end

        def view
          lines = ["#{Theme.accent(Theme::CURSOR)} #{Theme.bold(@label)}"]
          window.each { |index| lines << choice_line(index) }
          lines << "  #{Theme.muted(hint)}"
          lines << "  #{Theme.danger(Theme::CROSS)} #{Theme.danger(@error)}" if @error
          lines.join("\n")
        end

        private

        def choice_line(index)
          display = @choices[index].first
          box = @checked.include?(index) ? Theme.ok(Theme::CHECKED) : Theme.muted(Theme::UNCHECKED)
          pointer = index == @cursor ? Theme.accent(Theme::CURSOR) : ' '
          text = index == @cursor ? Theme.accent(display) : display
          "  #{pointer} #{box} #{text}"
        end

        def hint
          counter = "#{@checked.length}/#{@choices.length} selected"
          "space toggle · a all · enter confirm · esc back · #{counter}"
        end

        # The spacebar arrives as KEY_SPACE from some terminals and as a plain
        # ' ' rune from others; KeyMessage#space? only recognises the first, so
        # relying on it alone makes the toggle key dead on half of them.
        def space?(message)
          message.space? || message.to_s == ' '
        end

        def move(delta)
          @cursor = (@cursor + delta) % @choices.length
        end

        def toggle
          @checked.include?(@cursor) ? @checked.delete(@cursor) : @checked.add(@cursor)
          @error = nil
        end

        # All-or-nothing on one key: with eight services enabled, ticking each
        # in turn is the most common thing the old checkbox prompt made tedious.
        def toggle_all
          @checked = @checked.length == @choices.length ? Set.new : (0...@choices.length).to_set
          @error = nil
        end

        def submit
          if @checked.empty?
            @error = 'select at least one — space to tick, a for all'
            return
          end

          @done = true
        end

        def window
          return (0...@choices.length) if @choices.length <= WINDOW

          start = [[@cursor - (WINDOW / 2), 0].max, @choices.length - WINDOW].min
          (start...(start + WINDOW))
        end
      end
    end
  end
end
