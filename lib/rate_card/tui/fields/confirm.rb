# frozen_string_literal: true

module RateCard
  module TUI
    module Fields
      # The last gate before production is touched. Defaults to "no" and takes
      # an explicit y: enter alone declines, so a held-down return key from the
      # previous field cannot start a run by itself.
      class Confirm
        attr_reader :label

        def initialize(label:)
          @label = label
          @value = nil
        end

        def done? = !@value.nil?
        def value = @value

        def update(message)
          return nil unless message.is_a?(Bubbletea::KeyMessage)

          case message.to_s
          when 'y', 'Y' then @value = true
          when 'n', 'N' then @value = false
          else @value = false if message.enter?
          end
          nil
        end

        def view
          "#{Theme.accent(Theme::CURSOR)} #{Theme.bold(@label)} " \
            "#{Theme.muted('[y/N]')}"
        end
      end
    end
  end
end
