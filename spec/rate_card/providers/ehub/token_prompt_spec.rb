# frozen_string_literal: true

require 'base64'
require 'stringio'

RSpec.describe RateCard::Providers::EHub::TokenPrompt do
  def jwt_for(customer_id, email)
    encode = ->(h) { Base64.urlsafe_encode64(JSON.generate(h), padding: false) }
    "#{encode.call({ alg: 'none' })}." \
      "#{encode.call({ data: { user: { customer_id: customer_id, email: email } } })}.sig"
  end

  let(:token) { jwt_for(1042, 'ops@acme.test') }
  let(:out) { StringIO.new }
  let(:ui) { RateCard::UI.new(io: out) }

  it 'returns a token that decodes' do
    expect(described_class.read(ui: ui, io: StringIO.new("#{token}\n"))).to eq(token)
  end

  it 'strips the newline and surrounding whitespace a paste can carry' do
    expect(described_class.read(ui: ui, io: StringIO.new("  #{token}  \n"))).to eq(token)
  end

  # The whole reason this prompt is not a TUI field.
  it 'accepts a long token arriving as one write' do
    long = jwt_for(1042, "#{'a' * 300}@acme.test")

    expect(described_class.read(ui: ui, io: StringIO.new("#{long}\n"))).to eq(long)
  end

  it 're-prompts rather than giving up when the token is malformed' do
    io = StringIO.new("not-a-jwt\n#{token}\n")

    expect(described_class.read(ui: ui, io: io)).to eq(token)
    expect(out.string).to include('paste the token again')
  end

  # A silent `next` here reprinted the prompt with no explanation, so a leading
  # newline in the pasted clipboard content read as a double prompt or a hang.
  it 'says why it is asking again when the line was blank' do
    io = StringIO.new("\n#{token}\n")

    expect(described_class.read(ui: ui, io: io)).to eq(token)
    expect(out.string).to include('no token on that line')
  end

  # The blank line is not a malformed token, and saying so would send the user
  # looking for a problem with a token they had not pasted yet.
  it 'does not call a blank line a malformed token' do
    described_class.read(ui: ui, io: StringIO.new("\n#{token}\n"))

    expect(out.string).not_to include('paste the token again')
  end

  it 'returns nil on EOF so the caller can cancel cleanly' do
    expect(described_class.read(ui: ui, io: StringIO.new(''))).to be_nil
  end

  # A prior run that didn't shut down cleanly can leave the terminal in
  # bracketed paste mode (observed on iTerm2, which persists that mode across
  # process launches within a pane); the next paste then arrives wrapped in
  # the terminal's own markers.
  it 'strips a leftover bracketed-paste wrapper from a stuck terminal mode' do
    io = StringIO.new("\e[200~#{token}\e[201~\n")

    expect(described_class.read(ui: ui, io: io)).to eq(token)
  end
end
