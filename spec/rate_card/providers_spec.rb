# frozen_string_literal: true

RSpec.describe RateCard::Providers do
  describe '.all' do
    it 'lists the registered provider keys' do
      expect(described_class.all).to eq([:ehub])
    end
  end

  describe '.build' do
    it 'builds the eHub provider' do
      expect(described_class.build(:ehub)).to be_a(RateCard::Providers::EHub::Provider)
    end

    it 'raises on an unregistered key' do
      expect { described_class.build(:nope) }.to raise_error(ArgumentError, /nope/)
    end
  end
end
