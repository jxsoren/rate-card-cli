# frozen_string_literal: true

require 'bubbletea'
require 'bubbles'

module RateCard
  module TUI
    # The interactive session as one Elm-architecture model: catalogue lookup,
    # the wizard answers, the confirm, and the fetch. The token is read before
    # this starts — see TokenPrompt.
    #
    # This replaces Wizard. The prompts no longer block — there is one event
    # loop and one #update, and each answered field advances @stage — so the
    # flow that used to read top-to-bottom now reads as the STAGES list plus
    # #field_for. That is the cost of the architecture; what it buys is a run
    # that can show progress and failures live, and a recap you can go back and
    # amend without losing the token.
    #
    # It produces #spec and #grid for the caller to report on after the loop
    # exits. Nothing here writes files or prints tables.
    class App
      include Bubbletea::Model

      # No :token stage — see TokenPrompt for why it cannot live in the loop.
      STAGES = %i[
        loading carrier services zones unit weights package_type
        rate_keys confirm fetching
      ].freeze

      attr_reader :spec, :grid, :error, :notifier

      # notifier is set by the caller to the Bubbletea::Runner, whose #send is
      # the only way a worker thread can get a message onto the event loop.
      attr_writer :notifier

      def initialize(token:, output_base:,
                     client_factory: ->(tok) { Client.new(token: tok) })
        @token = token
        @output_base = Pathname.new(output_base)
        @client_factory = client_factory

        @stage = :loading
        @answers = {}
        @field = nil
        @cancelled = false
        @error = nil
        @spinner = Bubbles::Spinner.new
        @progress = Bubbles::Progress.new(width: 32)
        @completed = 0
        @failed = 0
        @log = []
      end

      def cancelled? = @cancelled

      def init
        [self, start_loading]
      end

      def update(message)
        return [self, Bubbletea.quit] if quit_key?(message)

        case message
        when ServicesLoaded    then services_loaded(message.services)
        when LoadFailed        then return fail_with(message.error)
        when ProgressAdvanced  then progress_advanced(message)
        when FetchFinished     then return finish(message.grid)
        when FetchFailed       then return fail_with(message.error)
        else
          return [self, spinner_or_field(message)]
        end

        [self, nil]
      end

      def view
        transcript = @log.compact
        sections = []
        sections << transcript.join("\n") unless transcript.empty?
        sections << stage_view
        "#{sections.compact.join("\n\n")}\n"
      end

      private

      # ---------------------------------------------------------------- input

      # Ctrl-C during the fetch still quits: the run is abandoned, and the
      # caller sees a nil grid rather than a partial one presented as complete.
      def quit_key?(message)
        return false unless message.is_a?(Bubbletea::KeyMessage)
        return false unless message.to_s == 'ctrl+c'

        @cancelled = true
      end

      def spinner_or_field(message)
        return advance_spinner(message) if @stage == :loading || @stage == :fetching
        return nil if @field.nil?

        command = @field.update(message)
        return command unless @field.done?

        record(@stage, @field.value)
        advance
      end

      def advance_spinner(message)
        @spinner, command = @spinner.update(message)
        command
      end

      # -------------------------------------------------------------- staging

      def record(stage, value)
        @answers[stage] = value
        @log << answered_line(stage, value)
      end

      def advance
        loop do
          @stage = STAGES[STAGES.index(@stage) + 1]
          return start_loading if @stage == :loading
          return start_fetch if @stage == :fetching

          @field = field_for(@stage)
          # A stage with exactly one possible answer is decided, not asked.
          break unless @field.nil?
        end
        nil
      end

      def field_for(stage)
        case stage
        when :carrier      then carrier_field
        when :services     then services_field
        when :zones        then zones_field
        when :unit         then unit_field
        when :weights      then weights_field
        when :package_type then package_type_field
        when :rate_keys    then rate_keys_field
        when :confirm      then Fields::Confirm.new(label: 'Build this rate card?')
        end
      end

      # --------------------------------------------------------------- fields

      def carrier_field
        carriers = ServiceCatalog.group_by_carrier(@services).keys
        return nil if carriers.length <= 1

        Fields::Select.new(label: 'Carrier', choices: carriers.map { |c| [c, c] })
      end

      def services_field
        choices = @services.select { |service| service.carrier == carrier }
        Fields::MultiSelect.new(
          label: 'Services',
          choices: choices.map { |service| [service.label, service] }
        )
      end

      def zones_field
        available = Constants::Addresses.available_zones(carrier)
        default = "#{available.first}-#{available.last}"

        Fields::Text.new(
          label: 'Zones', default: default, hint: "available: #{default}",
          parse: lambda { |raw|
            zones = Input.parse_range(raw) & available
            raise ArgumentError, "no valid zones in that input (available: #{default})" if zones.empty?

            zones
          }
        )
      end

      def unit_field
        Fields::Select.new(label: 'Weight unit', choices: [['oz', :oz], ['lbs', :lbs]])
      end

      def weights_field
        Fields::Text.new(
          label: 'Weight range', default: Input::DEFAULT_WEIGHT_RANGE,
          hint: 'a range like 1-16, or a list like 1,4,8',
          parse: lambda { |raw|
            weights = Input.parse_range(raw).reject(&:zero?)
            raise ArgumentError, 'enter a range like 1-16 or a list like 1,4,8' if weights.empty?

            weights
          }
        )
      end

      # The union of what the selected services accept, so a contract type like
      # fedex_pak is offered and a type no selected service accepts is not.
      def package_type_field
        choices = @answers[:services].flat_map(&:package_types).uniq.sort
        choices = Input::PACKAGE_TYPES if choices.empty?
        if choices.length == 1
          @answers[:package_type] = choices.first
          return nil
        end

        Fields::Select.new(label: 'Package type', choices: choices.map { |t| [t, t] })
      end

      def rate_keys_field
        keys = RunSpec::RATE_KEY_FIELDS.keys
        Fields::MultiSelect.new(
          label: 'Rate columns',
          choices: keys.map { |key| [RunSpec::RATE_KEY_LABELS.fetch(key), key] },
          checked: (0...keys.length).to_a
        )
      end

      def carrier
        @answers[:carrier] || ServiceCatalog.group_by_carrier(@services).keys.first
      end

      # ------------------------------------------------------------ catalogue

      # A Proc command: Bubbletea runs it in a Thread and feeds the returned
      # message back through #update, which is how the lookup happens without
      # blocking the loop that draws the spinner.
      def start_loading
        client = @client_factory.call(@token)
        lambda do
          services = ServiceCatalog.from_response(client.fetch_services)
          if services.empty?
            LoadFailed.new(NoServices.new('the API returned no services for this token'))
          else
            ServicesLoaded.new(services)
          end
        rescue StandardError => e
          LoadFailed.new(e)
        end
      end

      def services_loaded(services)
        @services = services
        @log << "  #{Theme.ok(Theme::TICK)} #{Theme.bold(identity[:name])} " \
                "(#{identity[:customer_id]}) · #{services.length} services found"
        advance
      end

      # ---------------------------------------------------------------- fetch

      def start_fetch
        unless @answers[:confirm]
          @cancelled = true
          # Not :fetching — the runner renders once more on the way out, and
          # fetch_view would dereference a spec that was never built.
          @stage = :done
          return Bubbletea.quit
        end

        @spec = build_spec
        # Before the first call, so a bad path is not discovered after 128 of them.
        begin
          CsvWriter.ensure_writable!(@spec.output_base)
        rescue OutputNotWritable => e
          return fail_with(e).last
        end

        client = @client_factory.call(@token)
        notifier = @notifier
        spec = @spec

        lambda do
          completed = 0
          failed = 0
          mutex = Mutex.new
          grid = Grid.build(spec: spec, client: client, on_progress: lambda {
            mutex.synchronize { completed += 1 }
            notifier&.send(ProgressAdvanced.new(completed: completed, failed: failed))
          })
          FetchFinished.new(grid)
        rescue StandardError => e
          FetchFailed.new(e)
        end
      end

      def progress_advanced(message)
        @completed = message.completed
        @failed = message.failed
      end

      def finish(grid)
        @grid = grid
        [self, Bubbletea.quit]
      end

      def fail_with(error)
        @error = error
        [self, Bubbletea.quit]
      end

      def build_spec
        RunSpec.new(
          token: @token,
          customer_name: identity[:name],
          customer_id: identity[:customer_id],
          carrier: carrier,
          services: @answers[:services],
          zones: @answers[:zones],
          weight_unit: @answers[:unit],
          weights: @answers[:weights],
          package_type: @answers[:package_type],
          rate_keys: @answers[:rate_keys],
          output_base: @output_base,
          show_table: true,
          started_at: Time.now
        ).validate!
      end

      def identity
        @identity ||= Token.decode(@token)
      end

      # ----------------------------------------------------------------- view

      def stage_view
        case @stage
        when :loading  then "  #{@spinner.view} Loading available services"
        when :fetching then fetch_view
        when :done     then nil
        when :confirm  then "#{recap_view}\n\n#{@field.view}"
        else @field&.view
        end
      end

      # Everything the run will do, gathered in one block. The answers are also
      # in the transcript above, but they arrived one at a time over eight
      # screens; this is the only place they can be read against each other.
      def recap_view
        [
          "  #{Theme.bold(carrier)} · #{@answers[:services].map(&:name).join(', ')}",
          "  zones #{RunSpec.compact_range(@answers[:zones])} · " \
            "weights #{RunSpec.compact_range(@answers[:weights])} #{@answers[:unit]} · " \
            "#{@answers[:package_type]}",
          "  columns: #{@answers[:rate_keys].map { |k| RunSpec::RATE_KEY_LABELS.fetch(k) }.join(', ')}",
          "  #{Theme.bold(call_count.to_s)} rate calls against #{Theme.danger('production')}"
        ].join("\n")
      end

      def call_count
        @answers[:weights].length * @answers[:zones].length
      end

      def fetch_view
        total = @spec.call_count
        percent = total.zero? ? 0.0 : @completed.to_f / total
        line = "  #{@progress.view_as(percent)}  #{@completed}/#{total}"
        line += "  #{Theme.warning("#{Theme::ALERT} #{@failed} failed")}" if @failed.positive?
        "#{Theme.bold('  fetching rates')}\n#{line}"
      end

      # One line per answered stage, kept above the current field so the
      # transcript of the run stays on screen — the recap is then a summary of
      # what is already visible rather than the first chance to check it.
      def answered_line(stage, value)
        label = { carrier: 'carrier', services: 'services', zones: 'zones',
                  unit: 'unit', weights: 'weights', package_type: 'package',
                  rate_keys: 'columns' }[stage]
        return nil if label.nil?

        "  #{Theme.ok(Theme::TICK)} #{label}: #{Theme.bold(describe(stage, value))}"
      end

      def describe(stage, value)
        case stage
        when :services  then value.map(&:name).join(', ')
        when :zones     then RunSpec.compact_range(value)
        when :weights   then RunSpec.compact_range(value)
        when :rate_keys then value.map { |k| RunSpec::RATE_KEY_LABELS.fetch(k) }.join(', ')
        else value.to_s
        end
      end
    end
  end
end
