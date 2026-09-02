# frozen_string_literal: true

require 'bubbletea'
require 'bubbles'
require 'ntcharts'

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
        loading rate_mode carrier services zones unit weights package_type
        rate_keys confirm fetching
      ].freeze

      attr_reader :spec, :grid, :error, :notifier

      # notifier is set by the caller to the Bubbletea::Runner, whose #send is
      # the only way a worker thread can get a message onto the event loop.
      attr_writer :notifier

      def initialize(token:, output_base:,
                     client_factory: ->(tok) { Providers::EHub::Client.new(token: tok) })
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
        @failure_history = []
        @failure_sparkline = Ntcharts::Sparkline.new(32, 1)
        @failure_sparkline.style = Lipgloss::Style.new.foreground(Theme::WARNING)
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
        transcript = @log.filter_map { |entry| entry[:line] }
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
        return retreat if back_key?(message)

        command = @field.update(message)
        return command unless @field.done?

        value = @field.value
        # The recap's own Back row, which is the esc key by another name.
        return retreat if @stage == :confirm && value == :back

        record(@stage, value)
        advance
      end

      # Esc, at any field including the confirm. The fields never see it, so
      # none of them has to know about the wizard it sits in.
      def back_key?(message)
        message.is_a?(Bubbletea::KeyMessage) && message.esc?
      end

      def advance_spinner(message)
        @spinner, command = @spinner.update(message)
        command
      end

      # -------------------------------------------------------------- staging

      def record(stage, value)
        @answers[stage] = value
        @log << { stage: stage, line: answered_line(stage, value) }
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

      # Steps back to the nearest earlier stage that actually asked something,
      # skipping the ones that were decided rather than asked. The answer being
      # revisited seeds the field, and every answer after it is forgotten —
      # they were given against a choice that may be about to change.
      def retreat
        index = STAGES.index(@stage)
        loop do
          index -= 1
          stage = STAGES[index]
          return nil if index.negative? || stage.nil? || stage == :loading

          field = field_for(stage)
          next if field.nil?

          forget_from(stage)
          @stage = stage
          @field = field
          return nil
        end
      end

      def forget_from(stage)
        dropped = STAGES[STAGES.index(stage)..]
        dropped.each { |name| @answers.delete(name) }
        @log.reject! { |entry| dropped.include?(entry[:stage]) }
      end

      def field_for(stage)
        case stage
        when :rate_mode    then rate_mode_field
        when :carrier      then carrier_field
        when :services     then services_field
        when :zones        then zones_field
        when :unit         then unit_field
        when :weights      then weights_field
        when :package_type then package_type_field
        when :rate_keys    then rate_keys_field
        when :confirm      then confirm_field
        end
      end

      # --------------------------------------------------------------- fields

      # The last gate before production is touched. It opens on Back, not on
      # Run: the field before it is also confirmed with enter, so a held-down
      # return key must not be able to start 128 production calls by itself.
      def confirm_field
        Fields::Select.new(label: 'Run this rate card?',
                           choices: [['Run', :run], ['Back', :back]], selected: 1)
      end

      # Only asked when the token has at least one USPS service — cubic
      # pricing is USPS-only, so a token with none has nothing to offer here
      # and the question is decided as :weight and skipped, same as every
      # other single-answer stage.
      def rate_mode_field
        return nil unless @services.any? { |service| service.carrier == 'USPS' }

        choices = [['Weight', :weight], ['Cubic dimensions', :cubic]]
        Fields::Select.new(label: 'Rate by', choices: choices,
                           selected: choices.index { |_, mode| mode == @answers[:rate_mode] } || 0)
      end

      def carrier_field
        carriers = selectable_carriers
        return nil if carriers.length <= 1

        Fields::Select.new(label: 'Carrier', choices: carriers.map { |c| [c, c] },
                           selected: carriers.index(@answers[:carrier]) || 0)
      end

      # Only carriers we hold a zone chart for. A service whose carrier has no
      # chart is dropped from the menu rather than offered and then refused
      # mid-run by Addresses.for_carrier.
      def selectable_carriers
        carriers = Providers::EHub::ServiceCatalog.group_by_carrier(@services)
                                 .keys
                                 .select { |carrier| Constants::Addresses.supported?(carrier) }
        return carriers & ['USPS'] if @answers[:rate_mode] == :cubic

        carriers
      end

      def services_field
        choices = @services.select { |service| service.carrier == carrier }
        Fields::MultiSelect.new(
          label: 'Services',
          choices: choices.map { |service| [service.label, service] },
          checked: checked_indexes(choices, @answers[:services])
        )
      end

      def zones_field
        available = Constants::Addresses.available_zones(carrier)
        full = "#{available.first}-#{available.last}"
        answered = @answers[:zones]

        Fields::Text.new(
          label: 'Zones', default: answered ? RunSpec.compact_range(answered) : full,
          hint: "available: #{full}",
          parse: lambda { |raw|
            zones = Input.parse_range(raw) & available
            raise ArgumentError, "no valid zones in that input (available: #{full})" if zones.empty?

            zones
          }
        )
      end

      # Weight is fixed per cubic tier, so asking for a display unit is
      # meaningless in cubic mode — decided as :oz (unused) and skipped.
      def unit_field
        return nil if @answers[:rate_mode] == :cubic

        choices = [['oz', :oz], ['lbs', :lbs]]
        Fields::Select.new(label: 'Weight unit', choices: choices,
                           selected: choices.index { |_, unit| unit == @answers[:unit] } || 0)
      end

      def weights_field
        return cubic_tiers_field if @answers[:rate_mode] == :cubic

        answered = @answers[:weights]

        Fields::Text.new(
          label: 'Weight range',
          default: answered ? RunSpec.compact_range(answered) : Input::DEFAULT_WEIGHT_RANGE,
          hint: 'a range like 1-16, or a list like 1,4,8',
          parse: lambda { |raw|
            weights = Input.parse_range(raw).reject(&:zero?)
            raise ArgumentError, 'enter a range like 1-16 or a list like 1,4,8' if weights.empty?

            weights
          }
        )
      end

      # Stored under the same @answers[:weights] key the weight-range text
      # field uses (an array of ids rather than an array of weights) so
      # #advance, #retreat and #build_spec do not need a third answer slot.
      def cubic_tiers_field
        choices = Constants::CubicTiers.choices
        answered = @answers[:weights]
        Fields::MultiSelect.new(
          label: 'Cubic tiers',
          choices: choices,
          checked: answered ? checked_indexes(choices.map(&:last), answered) : (0...choices.length)
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

        Fields::Select.new(label: 'Package type', choices: choices.map { |t| [t, t] },
                           selected: choices.index(@answers[:package_type]) || 0)
      end

      def rate_keys_field
        keys = RunSpec::RATE_KEY_FIELDS.keys
        Fields::MultiSelect.new(
          label: 'Rate columns',
          choices: keys.map { |key| [RunSpec::RATE_KEY_LABELS.fetch(key), key] },
          checked: @answers[:rate_keys] ? checked_indexes(keys, @answers[:rate_keys]) : (0...keys.length)
        )
      end

      # Which rows a re-entered multi-select opens with ticked. Values that are
      # no longer on offer — a service dropped by a carrier change — are simply
      # not found, and so are not carried forward.
      def checked_indexes(choices, answered)
        return [] if answered.nil?

        answered.filter_map { |value| choices.index(value) }
      end

      def carrier
        @answers[:carrier] || selectable_carriers.first
      end

      # ------------------------------------------------------------ catalogue

      # A Proc command: Bubbletea runs it in a Thread and feeds the returned
      # message back through #update, which is how the lookup happens without
      # blocking the loop that draws the spinner.
      def start_loading
        client = @client_factory.call(@token)
        lambda do
          services = Providers::EHub::ServiceCatalog.from_response(client.fetch_services)
          if services.empty?
            LoadFailed.new(NoServices.new('the API returned no services for this token'))
          elsif (rateable = with_supported_carrier(services)).empty?
            LoadFailed.new(UnsupportedCarrier.new(unsupported_message(services)))
          else
            ServicesLoaded.new(rateable)
          end
        rescue StandardError => e
          LoadFailed.new(e)
        end
      end

      def with_supported_carrier(services)
        services.select { |service| Constants::Addresses.supported?(service.carrier) }
      end

      def unsupported_message(services)
        offered = services.map(&:carrier).uniq.sort.join(', ')
        "this token's services are all on carriers with no curated zone chart " \
          "(#{offered}) — rate cards are only available for " \
          "#{Constants::Addresses.supported_carriers.join(', ')}"
      end

      def services_loaded(services)
        @services = services
        @log << { stage: :loading, line: "  #{Theme.ok(Theme::TICK)} #{Theme.bold(identity[:name])} " \
                "(#{identity[:customer_id]}) · #{services.length} services found" }
        advance
      end

      # ---------------------------------------------------------------- fetch

      def start_fetch
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
        @failure_history << message.failed
        @failure_sparkline.push(message.failed)
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
        cubic = @answers[:rate_mode] == :cubic
        RunSpec.new(
          token: @token,
          customer_name: identity[:name],
          customer_id: identity[:customer_id],
          carrier: carrier,
          services: @answers[:services],
          zones: @answers[:zones],
          weight_unit: @answers[:unit] || :oz,
          weights: cubic ? [] : @answers[:weights],
          cubic_tiers: cubic ? @answers[:weights] : [],
          rate_mode: @answers[:rate_mode] || :weight,
          package_type: @answers[:package_type],
          rate_keys: @answers[:rate_keys],
          output_base: @output_base,
          show_table: true,
          started_at: Time.now
        ).validate!
      end

      def identity
        @identity ||= Providers::EHub::Token.decode(@token)
      end

      # ----------------------------------------------------------------- view

      def stage_view
        case @stage
        when :loading  then "  #{@spinner.view} Loading available services"
        when :fetching then fetch_view
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
          "  zones #{RunSpec.compact_range(@answers[:zones])} · #{rows_recap} · #{@answers[:package_type]}",
          "  columns: #{@answers[:rate_keys].map { |k| RunSpec::RATE_KEY_LABELS.fetch(k) }.join(', ')}",
          "  #{Theme.bold(call_count.to_s)} rate calls against #{Theme.danger('production')}"
        ].join("\n")
      end

      def rows_recap
        if @answers[:rate_mode] == :cubic
          "cubic tiers #{RunSpec.compact_range(@answers[:weights])}"
        else
          "weights #{RunSpec.compact_range(@answers[:weights])} #{@answers[:unit]}"
        end
      end

      def call_count
        @answers[:weights].length * @answers[:zones].length
      end

      def fetch_view
        total = @spec.call_count
        percent = total.zero? ? 0.0 : @completed.to_f / total
        line = "  #{@progress.view_as(percent)}  #{@completed}/#{total}"
        line += "  #{Theme.warning("#{Theme::ALERT} #{@failed} failed")}" if @failed.positive?
        view = "#{Theme.bold('  fetching rates')}\n#{line}"
        view += "\n#{failure_sparkline_view}" if @failed.positive?
        view
      end

      # Only drawn once a failure has happened: a spark line of zeroes for a
      # clean run would be noise, not signal. It stays once shown even if
      # later ticks are all clean — the failure already happened.
      def failure_sparkline_view
        @failure_sparkline.draw_braille
        "  #{@failure_sparkline.view}"
      end

      # One line per answered stage, kept above the current field so the
      # transcript of the run stays on screen — the recap is then a summary of
      # what is already visible rather than the first chance to check it.
      def answered_line(stage, value)
        label = { rate_mode: 'rate by', carrier: 'carrier', services: 'services', zones: 'zones',
                  unit: 'unit', weights: 'weights', package_type: 'package',
                  rate_keys: 'columns' }[stage]
        label = 'cubic tiers' if stage == :weights && @answers[:rate_mode] == :cubic
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
