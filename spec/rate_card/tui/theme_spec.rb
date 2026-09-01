# frozen_string_literal: true

RSpec.describe RateCard::TUI::Theme do
  # Piped output (RSpec's captured stdout) is not a tty, so Lipgloss strips
  # color regardless of AdaptiveColor vs. a fixed color — these assertions
  # are about the constants being AdaptiveColor and the helpers not raising,
  # not about literal escape codes.
  described_instance = described_class

  it 'defines every semantic color as an adaptive light/dark pair' do
    %i[ACCENT OK WARNING DANGER MUTED].each do |name|
      color = described_instance.const_get(name)
      expect(color).to be_a(Lipgloss::AdaptiveColor)
      expect(color.light).to be_a(String)
      expect(color.dark).to be_a(String)
    end
  end

  it 'renders every helper without raising' do
    expect { described_class.accent('x') }.not_to raise_error
    expect { described_class.ok('x') }.not_to raise_error
    expect { described_class.warning('x') }.not_to raise_error
    expect { described_class.danger('x') }.not_to raise_error
    expect { described_class.muted('x') }.not_to raise_error
    expect { described_class.bold('x') }.not_to raise_error
    expect { described_class.title('x') }.not_to raise_error
    expect { described_class.banner }.not_to raise_error
  end

  it 'returns the plain text back when stdout is not a tty' do
    expect(described_class.accent('hello')).to eq('hello')
  end
end
