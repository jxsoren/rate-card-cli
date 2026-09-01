# frozen_string_literal: true

require 'support/keys'

RSpec.describe RateCard::TUI::Fields::MultiSelect do
  def build(**overrides)
    described_class.new(**{ label: 'Services', choices: [%w[A a], %w[B b], %w[C c]] }
      .merge(overrides))
  end

  it 'starts with nothing ticked and is not done' do
    field = build

    expect(field).not_to be_done
    expect(field.value).to eq([])
  end

  it 'ticks the choice under the cursor with space' do
    field = build
    field.update(Keys.space)

    expect(field.value).to eq(['a'])
  end

  # Terminals disagree on how the spacebar arrives; both must toggle.
  it 'also ticks on a plain space rune' do
    field = build
    field.update(Keys.space_rune)

    expect(field.value).to eq(['a'])
  end

  it 'unticks a ticked choice' do
    field = build
    2.times { field.update(Keys.space) }

    expect(field.value).to eq([])
  end

  it 'moves the cursor and ticks the choice it lands on' do
    field = build
    field.update(Keys.down)
    field.update(Keys.space)

    expect(field.value).to eq(['b'])
  end

  it 'wraps the cursor from the top to the bottom' do
    field = build
    field.update(Keys.up)
    field.update(Keys.space)

    expect(field.value).to eq(['c'])
  end

  it "ticks everything with 'a', and unticks everything on a second press" do
    field = build
    field.update(Keys.char('a'))
    expect(field.value).to eq(%w[a b c])

    field.update(Keys.char('a'))
    expect(field.value).to eq([])
  end

  it 'confirms with enter once something is ticked' do
    field = build
    field.update(Keys.space)
    field.update(Keys.enter)

    expect(field).to be_done
    expect(field.value).to eq(['a'])
  end

  # An empty answer would otherwise surface much later, as a validate! failure.
  it 'refuses an empty selection and says so rather than confirming' do
    field = build
    field.update(Keys.enter)

    expect(field).not_to be_done
    expect(field.error).to include('at least one')
    expect(field.view).to include('at least one')
  end

  it 'clears the error once something is ticked' do
    field = build
    field.update(Keys.enter)
    field.update(Keys.space)

    expect(field.error).to be_nil
  end

  it 'honours choices ticked on entry' do
    field = build(checked: [0, 2])

    expect(field.value).to eq(%w[a c])
  end

  it 'shows a running count of what is ticked' do
    field = build(checked: [0])

    expect(field.view).to include('1/3 selected')
  end

  it 'windows a long list so it cannot push the rest of the screen away' do
    field = build(choices: (1..30).map { |n| ["S#{n}", n] })

    expect(field.view.lines.length).to be <= described_class::WINDOW + 3
  end
end
