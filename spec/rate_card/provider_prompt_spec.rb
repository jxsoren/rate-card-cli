# frozen_string_literal: true

require 'stringio'

RSpec.describe RateCard::ProviderPrompt do
  let(:out) { StringIO.new }
  let(:ui) { RateCard::UI.new(io: out) }

  it 'announces the sole registered provider and returns its key' do
    expect(described_class.read(ui: ui, keys: [:ehub])).to eq(:ehub)
    expect(out.string).to include('Provider: eHub')
  end

  it 'raises when more than one provider is registered, rather than silently picking one' do
    expect { described_class.read(ui: ui, keys: %i[ehub easypost]) }
      .to raise_error(ArgumentError, /multi-provider/)
  end
end
