# frozen_string_literal: true

require 'bubbletea'

module RateCard
  module TUI
    # Results of work done off the event loop. Bubbletea runs a Proc command in
    # a Thread and feeds whatever it returns back through #update, and the fetch
    # pushes ProgressAdvanced from its worker threads via Runner#send.
    class ServicesLoaded < Bubbletea::Message
      attr_reader :services

      def initialize(services)
        super()
        @services = services
      end
    end

    class LoadFailed < Bubbletea::Message
      attr_reader :error

      def initialize(error)
        super()
        @error = error
      end
    end

    # Carries the running failure count so the bar can show trouble as it
    # happens: on a doomed run the user should not have to wait out all 128
    # calls to find out.
    class ProgressAdvanced < Bubbletea::Message
      attr_reader :completed, :failed

      def initialize(completed:, failed:)
        super()
        @completed = completed
        @failed = failed
      end
    end

    class FetchFinished < Bubbletea::Message
      attr_reader :grid

      def initialize(grid)
        super()
        @grid = grid
      end
    end

    class FetchFailed < Bubbletea::Message
      attr_reader :error

      def initialize(error)
        super()
        @error = error
      end
    end
  end
end
