# frozen_string_literal: true

RSpec.describe RateCard::Input do
  describe '.parse_range' do
    it 'parses a dashed range' do
      expect(described_class.parse_range('1-4')).to eq([1, 2, 3, 4])
    end

    it 'parses a comma list' do
      expect(described_class.parse_range('1,3,5')).to eq([1, 3, 5])
    end

    it 'parses a mix of ranges and singles, sorted and deduplicated' do
      expect(described_class.parse_range('5,1-3,3')).to eq([1, 2, 3, 5])
    end

    it 'tolerates whitespace' do
      expect(described_class.parse_range(' 1 - 3 , 6 ')).to eq([1, 2, 3, 6])
    end

    it 'returns an empty array for unparseable input' do
      expect(described_class.parse_range('abc')).to eq([])
    end

    it 'ignores a reversed range rather than looping forever' do
      expect(described_class.parse_range('8-1')).to eq([])
    end
  end
end
