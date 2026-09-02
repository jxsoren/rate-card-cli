# frozen_string_literal: true

require 'open3'

RSpec.describe 'exe/rate-card' do
  def run_cli(*args, stdin: '')
    Open3.capture3({ 'BUNDLE_GEMFILE' => File.expand_path('../Gemfile', __dir__) },
                   'bundle', 'exec', File.expand_path('../exe/rate-card', __dir__), *args,
                   stdin_data: stdin)
  end

  it 'is executable' do
    expect(File.executable?(File.expand_path('../exe/rate-card', __dir__))).to be(true)
  end

  it 'prints the version and exits 0 for --version' do
    stdout, _stderr, status = run_cli('--version')

    # Against the constant, not a literal: a hardcoded version turns every
    # release into a failing spec, and bin/release gates the release on the
    # suite passing.
    expect(stdout).to include(RateCard::VERSION)
    expect(status.exitstatus).to eq(0)
  end

  it 'prints usage including both flags for --help' do
    stdout, _stderr, status = run_cli('--help')

    expect(stdout).to include('--output-dir')
    expect(stdout).to include('--no-table')
    expect(status.exitstatus).to eq(0)
  end

  it 'exits 1 with a one-line message and no backtrace for an unknown flag' do
    stdout, stderr, status = run_cli('--nope')

    expect(status.exitstatus).to eq(1)
    expect(stdout + stderr).not_to include('rate_card.rb:')
    expect(stdout + stderr).to match(/invalid option|unknown/i)
  end
end
