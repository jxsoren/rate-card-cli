# frozen_string_literal: true

require 'bubbletea'

# Synthesises the key messages a terminal would send, so the TUI can be driven
# in a spec without a pty. This is the payoff of the Bubbletea switch: App and
# the fields are pure #update/#view, so nothing here has to fake a terminal —
# it only has to fake keystrokes.
module Keys
  module_function

  def key(key_type, name: nil)
    Bubbletea::KeyMessage.new(key_type: key_type, name: name)
  end

  def char(character)
    Bubbletea::KeyMessage.new(
      key_type: Bubbletea::KeyMessage::KEY_RUNES,
      runes: character.unpack('U*')
    )
  end

  def type(text)
    text.each_char.map { |character| char(character) }
  end

  def enter = key(Bubbletea::KeyMessage::KEY_ENTER)
  def space = key(Bubbletea::KeyMessage::KEY_SPACE)

  # What terminals that do not send KEY_SPACE send instead.
  def space_rune = char(' ')
  def up    = key(Bubbletea::KeyMessage::KEY_UP)
  def down  = key(Bubbletea::KeyMessage::KEY_DOWN)
  def esc = key(Bubbletea::KeyMessage::KEY_ESC)
  def ctrl_c = key(Bubbletea::KeyMessage::KEY_CTRL_C)
end
