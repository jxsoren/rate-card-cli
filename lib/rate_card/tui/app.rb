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
        loading rate_mode carrier rural rural_surcharges services country gls_origin zones unit weights
        package_type rate_keys add_another confirm fetching
      ].freeze

      # #spec/#grid hold the most recently finished pass, for every caller that
      # only ever produced one (every carrier except UPS rural mode with more
      # than one surcharge type checked). #results holds every pass.
      attr_reader :spec, :grid, :error, :notifier, :results

      # notifier is set by the caller to the Bubbletea::Runner, whose #send is
      # the only way a worker thread can get a message onto the event loop.
      attr_writer :notifier

      def initialize(token:, output_base:, provider:,
                     client_factory: ->(tok) { provider.client(tok) })
        @token = token
        @output_base = Pathname.new(output_base)
        @provider = provider
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
        @results = []
        @queued_specs = []
        @queued_scenarios = []
        @scenario = 1
        @log << { stage: :scenario_header, line: scenario_header_line(@scenario) }
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
        when FetchFinished     then return fetch_finished(message.grid)
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
        return add_another_chosen(value) if @stage == :add_another

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
      rescue RequestFailed, UnsupportedCarrier => e
        fail_with(e).last
      end

      # Steps back to the nearest earlier stage that actually asked something,
      # skipping the ones that were decided rather than asked. The answer being
      # revisited seeds the field, and every answer after it is forgotten —
      # they were given against a choice that may be about to change.
      def retreat
        return confirm_back if @stage == :confirm

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

      # Esc from confirm must not re-run the wizard's forget-forward logic -
      # the scenario just chosen at add_another is already queued and its
      # answers already cleared (#confirm_or_queue), so there is nothing left
      # to forget. It simply reopens the add_another question.
      def confirm_back
        @stage = :add_another
        @field = field_for(:add_another)
        nil
      end

      # add_another is now asked as soon as every field is filled in, before
      # the run is ever confirmed. Either choice queues the just-answered
      # scenario. Yes clears @answers and jumps back to the wizard's first
      # real question for a fresh scenario; No moves on to the confirm
      # screen, which then asks to run the whole queue.
      def add_another_chosen(value)
        confirm_or_queue
        return advance_to_confirm if value == :no

        @scenario += 1
        @log << { stage: :scenario_header, line: scenario_header_line(@scenario) }

        @stage = STAGES.first
        loop do
          @stage = STAGES[STAGES.index(@stage) + 1]
          @field = field_for(@stage)
          break unless @field.nil?
        end
        nil
      rescue RequestFailed, UnsupportedCarrier => e
        fail_with(e).last
      end

      def advance_to_confirm
        @stage = :confirm
        @field = field_for(:confirm)
        nil
      end

      def scenario_header_line(number)
        "\n#{Theme.title("Scenario #{number}")}"
      end

      # Commits the just-confirmed scenario's specs (today's build_specs,
      # unchanged) to the queue and clears @answers so the next pass through
      # the wizard, or #start_fetch, starts from a blank slate. Also grouped
      # under @queued_scenarios, one entry per wizard pass, so the confirm
      # recap can show each scenario as its own block rather than one flat
      # list of specs.
      def confirm_or_queue
        specs = build_specs
        @queued_specs.concat(specs)
        @queued_scenarios << specs
        @log << { stage: :add_another, line: queued_summary_line(specs) }
        @answers = {}
      end

      def queued_summary_line(specs)
        "  #{Theme.ok(Theme::TICK)} queued: #{Theme.bold(specs.first.carrier)} — #{specs.sum(&:call_count)} calls"
      end

      def forget_from(stage)
        dropped = STAGES[STAGES.index(stage)..]
        dropped.each { |name| @answers.delete(name) }
        @log.reject! { |entry| dropped.include?(entry[:stage]) }
      end

      def field_for(stage)
        case stage
        when :rate_mode        then rate_mode_field
        when :carrier          then carrier_field
        when :rural            then rural_field
        when :rural_surcharges then rural_surcharges_field
        when :services         then services_field
        when :country          then country_field
        when :gls_origin       then gls_origin_field
        when :zones        then zones_field
        when :unit         then unit_field
        when :weights      then weights_field
        when :package_type then package_type_field
        when :rate_keys    then rate_keys_field
        when :add_another  then add_another_field
        when :confirm      then confirm_field
        end
      end

      # --------------------------------------------------------------- fields

      # Reached as soon as every field for the current scenario is filled in.
      # Yes clears @answers and jumps back to the top of the wizard for a
      # fresh scenario; No moves on to the confirm screen for the whole queue.
      def add_another_field
        Fields::Select.new(
          label: 'Add another scenario?',
          choices: [['Yes, add another', :yes],
                    ["No, continue to run #{@queued_specs.length + 1} scenario(s)", :no]],
          selected: 0
        )
      end

      # The last gate before production is touched. It opens on Back, not on
      # Run: the field before it is also confirmed with enter, so a held-down
      # return key must not be able to start 128 production calls by itself.
      # The label names the whole queue once there is more than one scenario
      # in it, so "Run" is never ambiguous about how many cards it fires off.
      def confirm_field
        label = @queued_scenarios.length > 1 ? "Run all #{@queued_scenarios.length} scenarios?" : 'Run this rate card?'
        Fields::Select.new(label: label,
                           choices: [['Run', :run], ['Back', :back]], selected: 1)
      end

      # Only asked when the token has at least one USPS service — cubic
      # pricing is USPS-only, so a token with none has nothing to offer here
      # and the question is decided as :weight and skipped, same as every
      # other single-answer stage.
      def rate_mode_field
        return nil unless @services.any? { |service| service.carrier == 'USPS' }

        choices = [['Weight', :weight], ['Cubic', :cubic]]
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
        carriers = Service.group_by_carrier(@services)
                                 .keys
                                 .select do |carrier|
                                   Constants::Addresses.supported?(carrier) || Constants::Carriers.live_chart?(carrier)
                                 end
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

      # Only USPS and UPS have a rural/DAS chart (Addresses::USPS_RURAL_DAS,
      # Addresses::UPS_RURAL); every other carrier is decided :normal (nil)
      # and skips this stage, same as any other single-answer stage. Same
      # Normal/Rural toggle for both carriers - which surcharge type(s) UPS
      # means by "rural" is a separate question, :rural_surcharges below.
      def rural_field
        return nil unless Constants::Carriers.rural_aware?(carrier)

        choices = [['Standard', false], ['Rural (DAS)', true]]
        Fields::Select.new(label: 'Address Type', choices: choices,
                           selected: choices.index { |_, v| v == @answers[:rural] } || 0)
      end

      # UPS has no per-zone rural chart - each surcharge type is one fixed
      # address, not a zone sweep - so this replaces the zones question for
      # UPS rural mode. Checking both produces two separate rate cards (see
      # #build_specs), one per surcharge type, rather than one card that
      # conflates two different addresses under one "zone" axis.
      def rural_surcharges_field
        return nil unless ups_rural?

        choices = [['EDAS', :edas], ['RDAS', :rdas]]
        answered = @answers[:rural_surcharges]
        Fields::MultiSelect.new(
          label: 'Surcharge types',
          choices: choices,
          checked: answered ? checked_indexes(choices.map(&:last), answered) : (0...choices.length)
        )
      end

      # Only offered for international-aware carriers (USPS today, via
      # USPS_CANADA_ORIGINS/USPS_CANADA_DESTINATION), and dropped whenever
      # rural mode is on - USPS rural DAS is its own fixed domestic chart,
      # not something international mode should combine with.
      def country_field
        return nil unless Constants::Carriers.international_aware?(carrier)
        return nil if @answers[:rural]

        choices = [['Domestic', nil], ['Canada', 'CA']]
        Fields::Select.new(label: 'Destination', choices: choices,
                           selected: choices.index { |_, v| v == @answers[:country] } || 0)
      end

      def zones_field
        return nil if ups_rural?

        available = live_zones_for(carrier)
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

      def usps_rural?
        carrier == 'USPS' && @answers[:rural] == true
      end

      def ups_rural?
        carrier == 'UPS' && @answers[:rural] == true
      end

      # Only asked for GLS: a fixed-origin carrier whose live zone chart is
      # computed from the shipment's origin postal code rather than an
      # account-configured hub, same reasoning as USPS/UPS/FedEx's shipment
      # origin — but that origin only feeds fetch_zone_addresses' lookup, it
      # is not itself a shipment field.
      def gls_origin_field
        return nil unless carrier == 'GLS'

        Fields::Text.new(
          label: 'GLS origin postal code',
          default: @answers[:gls_origin] || Constants::Addresses::ORIGIN[:postal_code],
          hint: 'GLS zone is computed from this origin, not your account',
          parse: lambda { |raw|
            raise ArgumentError, 'enter a postal code' if raw.strip.empty?

            raw.strip
          }
        )
      end

      def live_zones_for(carrier)
        return Constants::Addresses::USPS_CANADA_ORIGINS.keys.sort if carrier == 'USPS' && @answers[:country] == 'CA'
        return Constants::Addresses.available_zones(carrier) unless Constants::Carriers.live_chart?(carrier)

        live_chart(carrier).keys.sort
      end

      # Memoized per (carrier, run) — the endpoint gets hit once even though
      # zones_field, and later address_for per selected zone, both need the chart.
      def live_chart(carrier)
        @live_charts ||= {}
        @live_charts[carrier] ||= fetch_live_chart(carrier)
      end

      def fetch_live_chart(carrier)
        service = @services.find { |s| s.carrier == carrier }
        raise UnsupportedCarrier, "no service_id found for #{carrier}" unless service

        client = @client_factory.call(@token)
        body = client.fetch_zone_addresses(service.id, from_postal_code: gls_origin_for(carrier))
        chart = (body['zones'] || {}).transform_keys(&:to_i)
                                      .transform_values { |address| symbolize(address) }
        if chart.empty?
          raise UnsupportedCarrier,
                "eHub found no real address for any zone for #{carrier} on this account yet"
        end

        chart
      end

      def gls_origin_for(carrier)
        carrier == 'GLS' ? (@answers[:gls_origin] || Constants::Addresses::ORIGIN[:postal_code]) : nil
      end

      def symbolize(hash)
        hash.to_h { |k, v| [k.to_sym, v] }
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
          services = @provider.parse_services(client.fetch_services)
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
        services.select do |service|
          Constants::Addresses.supported?(service.carrier) || Constants::Carriers.live_chart?(service.carrier)
        end
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

      # UPS rural mode with more than one surcharge type checked runs as
      # several independent passes (see #build_specs) - each one calls
      # Grid.build, feeds the same progress bar, and lands its own {spec:,
      # grid:} in #results before the next pass starts. Every other carrier
      # and mode has exactly one pass, same as before this existed.
      def start_fetch
        @pending_specs = @queued_specs.dup
        # Before the first call, so a bad path is not discovered after 128 of them.
        begin
          @pending_specs.each { |spec| CsvWriter.ensure_writable!(spec.output_base) }
        rescue OutputNotWritable => e
          return fail_with(e).last
        end

        @results = []
        @total_passes = @pending_specs.length
        @pass_index = 0
        next_pass
      end

      # Does not clear @spec when there is no next pass: Bubbletea renders once
      # more before a returned Bubbletea.quit actually stops the loop, and
      # that render still hits :fetching's view, which reads @spec. Leaving it
      # pointed at the just-finished pass keeps that last render honest rather
      # than crashing on a nil spec.
      def next_pass
        next_spec = @pending_specs.shift
        return Bubbletea.quit if next_spec.nil?

        @spec = next_spec
        @pass_index += 1
        @completed = 0
        @failed = 0
        fetch_command(@spec)
      end

      def fetch_command(spec)
        client = @client_factory.call(@token)
        notifier = @notifier
        provider = @provider

        lambda do
          completed = 0
          failed = 0
          mutex = Mutex.new
          grid = Grid.build(spec: spec, client: client, provider: provider, on_progress: lambda {
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

      def fetch_finished(grid)
        @grid = grid
        @results << { spec: @spec, grid: grid }
        [self, next_pass]
      end

      def fail_with(error)
        @error = error
        [self, Bubbletea.quit]
      end

      # One RunSpec per pass. UPS rural mode runs one pass per checked
      # surcharge type (each is a fixed single address, not a zone sweep -
      # see Addresses::UPS_RURAL) rather than folding both into one card's
      # zone axis. Every other carrier/mode is the single pass it always was.
      def build_specs
        if ups_rural?
          (@answers[:rural_surcharges] || []).map { |surcharge| run_spec(zones: [surcharge]) }
        else
          [run_spec(zones: @answers[:zones])]
        end
      end

      def build_spec
        build_specs.first
      end

      def run_spec(zones:)
        cubic = @answers[:rate_mode] == :cubic
        RunSpec.new(
          token: @token,
          customer_name: identity[:name],
          customer_id: identity[:customer_id],
          carrier: carrier,
          services: @answers[:services],
          zones: zones,
          weight_unit: @answers[:unit] || :oz,
          weights: cubic ? [] : @answers[:weights],
          cubic_tiers: cubic ? @answers[:weights] : [],
          rate_mode: @answers[:rate_mode] || :weight,
          rural: @answers[:rural],
          country: @answers[:country],
          package_type: @answers[:package_type],
          rate_keys: @answers[:rate_keys],
          zone_chart: Constants::Carriers.live_chart?(carrier) ? live_chart(carrier) : nil,
          output_base: @output_base,
          show_table: true,
          started_at: Time.now
        ).validate!
      end

      def identity
        @identity ||= @provider.identify(@token)
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

      # Everything every queued scenario will do, gathered in one block. By
      # the time confirm is reached, add_another has already queued the
      # current scenario and cleared @answers (#confirm_or_queue), so this
      # reads from @queued_scenarios/@queued_specs rather than @answers -
      # unlike the single-scenario recap this replaces, it has to summarize
      # everything already queued, not just what was just answered.
      def recap_view
        blocks = @queued_scenarios.map { |specs| scenario_recap_block(specs) }
        blocks << "  #{Theme.bold(@queued_specs.sum(&:call_count).to_s)} rate calls against #{Theme.danger('production')}" \
          "#{@queued_specs.length > 1 ? " (#{@queued_specs.length} separate cards)" : ''}"
        blocks.join("\n\n")
      end

      # One block per queued wizard pass. Almost always one spec; more than
      # one only for UPS rural mode with several surcharge types checked, in
      # which case every spec in the block shares carrier/services/package/
      # rate_keys and differs only in zones (see #build_specs).
      def scenario_recap_block(specs)
        first = specs.first
        [
          "  #{Theme.bold(first.carrier)}#{spec_rural_recap(first)} · #{first.services.map(&:name).join(', ')}",
          *specs.map { |spec| "  zones #{spec.zone_summary} · #{spec_rows_recap(spec)} · #{first.package_type}" },
          "  columns: #{first.rate_keys.map { |k| RunSpec::RATE_KEY_LABELS.fetch(k) }.join(', ')}"
        ].join("\n")
      end

      def spec_rural_recap(spec)
        return '' unless spec.rural

        " (#{rural_label(spec.rural)})"
      end

      def spec_rows_recap(spec)
        if spec.rate_mode == :cubic
          "cubic tiers #{RunSpec.compact_range(spec.cubic_tiers)}"
        else
          "weights #{RunSpec.compact_range(spec.weights)} #{spec.weight_unit}"
        end
      end

      def fetch_view
        total = @spec.call_count
        percent = total.zero? ? 0.0 : @completed.to_f / total
        title = @total_passes > 1 ? "fetching rates (pass #{@pass_index}/#{@total_passes})" : 'fetching rates'
        line = "  #{@progress.view_as(percent)}  #{@completed}/#{total}"
        line += "  #{Theme.warning("#{Theme::ALERT} #{@failed} failed")}" if @failed.positive?
        view = "#{Theme.bold("  #{title}")}\n#{line}"
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
        label = { rate_mode: 'rate by', carrier: 'carrier', rural: 'rural / DAS',
                  rural_surcharges: 'surcharge types', services: 'services',
                  country: 'destination', gls_origin: 'GLS origin', zones: 'zones',
                  unit: 'unit', weights: 'weights', package_type: 'package',
                  rate_keys: 'columns' }[stage]
        label = 'cubic tiers' if stage == :weights && @answers[:rate_mode] == :cubic
        return nil if label.nil?

        "  #{Theme.ok(Theme::TICK)} #{label}: #{Theme.bold(describe(stage, value))}"
      end

      def describe(stage, value)
        case stage
        when :services          then value.map(&:name).join(', ')
        when :zones             then RunSpec.compact_range(value)
        when :weights           then RunSpec.compact_range(value)
        when :rural             then rural_label(value)
        when :rural_surcharges  then value.map { |v| v.to_s.upcase }.join(', ')
        when :country           then value || 'Domestic'
        when :rate_keys         then value.map { |k| RunSpec::RATE_KEY_LABELS.fetch(k) }.join(', ')
        else value.to_s
        end
      end

      def rural_label(value)
        value ? 'rural (DAS)' : 'normal'
      end
    end
  end
end
