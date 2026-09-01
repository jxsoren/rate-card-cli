# frozen_string_literal: true

require 'stringio'
require 'pathname'

# The banner, the customer echo and the recap moved to TUI::App when the
# interactive half switched to Bubbletea; their coverage lives in app_spec.
# What is left here is the plain reporting printed after the loop exits.
RSpec.describe RateCard::UI do
  let(:io) { StringIO.new }
  subject(:ui) { described_class.new(io: io) }

  describe '#info / #warn / #error / #success' do
    it 'prints each message' do
      ui.info('probing')
      ui.warn('two cells failed')
      ui.error('token rejected')
      ui.success('saved')

      expect(io.string).to include('probing', 'two cells failed', 'token rejected', 'saved')
    end
  end

  describe '#print_tables' do
    it 'prints each table with its title' do
      ui.print_tables([['GA · shipper rate', "┌──┐\n│x │\n└──┘"]])

      expect(io.string).to include('GA · shipper rate')
      expect(io.string).to include('┌──┐')
    end
  end

  describe '#failure_report' do
    it 'prints nothing when there are no failures' do
      ui.failure_report([])

      expect(io.string).to eq('')
    end

    it 'lists each failed cell with its weight, zone and reason' do
      ui.failure_report([RateCard::Failure.new(weight: 14, zone: 7, message: 'HTTP 500')])

      expect(io.string).to include('1 cell failed')
      expect(io.string).to include('wt 14')
      expect(io.string).to include('Z7')
      expect(io.string).to include('HTTP 500')
    end

    it 'pluralises the count' do
      failures = [RateCard::Failure.new(weight: 1, zone: 1, message: 'a'),
                  RateCard::Failure.new(weight: 2, zone: 1, message: 'b')]
      ui.failure_report(failures)

      expect(io.string).to include('2 cells failed')
    end

    it 'collapses a long failure list to a summary after ten entries' do
      failures = (1..15).map { |i| RateCard::Failure.new(weight: i, zone: 1, message: 'HTTP 500') }
      ui.failure_report(failures)

      expect(io.string).to include('15 cells failed')
      expect(io.string).to include('5 more')
    end
  end

  describe '#warning_report' do
    it 'prints nothing when the API reported no warnings' do
      ui.warning_report([])

      expect(io.string).to eq('')
    end

    it 'prints each warning the API returned' do
      ui.warning_report([RateCard::Warning.new(message: 'FedEx returned error: bad zip', count: 1)])

      expect(io.string).to include('the API reported 1 warning')
      expect(io.string).to include('FedEx returned error: bad zip')
    end

    it 'shows how many calls repeated the same warning' do
      ui.warning_report([RateCard::Warning.new(message: 'carrier down', count: 12)])

      expect(io.string).to include('carrier down')
      expect(io.string).to include('×12')
    end

    it 'collapses a long warning list to a summary after ten entries' do
      warnings = (1..15).map { |i| RateCard::Warning.new(message: "w#{i}", count: 1) }
      ui.warning_report(warnings)

      expect(io.string).to include('15 warnings')
      expect(io.string).to include('5 more')
    end
  end

  describe '#saved' do
    it 'reports the destination directory and each filename' do
      ui.saved([Pathname.new('/tmp/run/GroundAdvantage_shipper_rate.csv')])

      expect(io.string).to include('/tmp/run')
      expect(io.string).to include('GroundAdvantage_shipper_rate.csv')
      expect(io.string).to include('Saved 1 file')
    end

    it 'pluralises the file count' do
      ui.saved([Pathname.new('/tmp/run/a.csv'), Pathname.new('/tmp/run/b.csv')])

      expect(io.string).to include('Saved 2 files')
    end
  end

  describe 'colour' do
    it 'emits no ansi escapes when the io is not a tty' do
      ui.success('done')

      expect(io.string).not_to include("\e[")
    end
  end
end
