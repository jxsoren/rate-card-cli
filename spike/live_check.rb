# frozen_string_literal: true
# Drives the real TUI under a pty against a fake API, so the event loop, the
# renderer and the terminal handoff are exercised — the specs only cover
# update/view.
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
$LOAD_PATH.unshift File.expand_path('../spec', __dir__)
require 'rate_card'
require 'support/fake_client'
require 'base64'
require 'tmpdir'

encode = ->(h) { Base64.urlsafe_encode64(JSON.generate(h), padding: false) }
TOKEN = "#{encode.call({ alg: 'none' })}." \
        "#{encode.call({ data: { user: { customer_id: 1042, email: 'ops@acme.test' } } })}.sig"

catalog = { 'services' => [{ 'service_id' => 1172, 'service_code' => 'GroundAdvantage',
                             'service' => 'USPS Ground Advantage', 'carrier_code' => 'usps' }] }
client = FakeClient.new(services: catalog) do |weight, _postal|
  sleep 0.002
  { 'service_rates' => [{ 'service_id' => 1172, 'rate' => weight * 1.5 }] }
end

Dir.mktmpdir do |dir|
  ui = RateCard::UI.new(io: $stdout)
  ui.banner
  tok = RateCard::TokenPrompt.read(ui: ui)
  abort 'LIVE: no token' if tok.nil?

  app = RateCard::TUI::App.new(token: tok, output_base: dir,
                               client_factory: ->(_t) { client })
  runner = Bubbletea::Runner.new(app)
  app.notifier = runner
  runner.run

  if app.cancelled?
    puts 'LIVE: cancelled'
  elsif app.error
    puts "LIVE: error #{app.error.class}: #{app.error.message}"
  else
    code = RateCard::Runner.new(spec: app.spec, grid: app.grid, ui: ui).run
    puts "LIVE: exit=#{code} calls=#{client.payloads.length}"
  end
end
