# frozen_string_literal: true

require 'base64'
require 'stringio'

RSpec.describe RateCard::TokenPrompt do
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

  it 'skips a blank line rather than treating it as an answer' do
    io = StringIO.new("\n#{token}\n")

    expect(described_class.read(ui: ui, io: io)).to eq(token)
    expect(out.string).not_to include('paste the token again')
  end

  it 'returns nil on EOF so the caller can cancel cleanly' do
    expect(described_class.read(ui: ui, io: StringIO.new(''))).to be_nil
  end
end
