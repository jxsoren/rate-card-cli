require 'bubbletea'
require 'bubbles'
class M
  include Bubbletea::Model
  def initialize = @log = []
  def update(m)
    case m
    when Bubbletea::KeyMessage
      return [self, Bubbletea.quit] if m.enter?
      @log << [m.key_type, m.runes.length, m.to_s]
    when Bubbles::TextInput::PasteMessage
      @log << [:paste, m.text.length, m.text]
    else
      @log << [m.class.name, 0, ''] unless m.is_a?(Bubbletea::WindowSizeMessage)
    end
    [self, nil]
  end
  def view = "got #{@log.length}"
  def report = @log
end
m = M.new
Bubbletea::Runner.new(m).run
warn "MESSAGES=#{m.report.length} RUNES_TOTAL=#{m.report.sum { |r| r[1] }}"
warn "TEXT=#{m.report.map { |r| r[2] }.join.inspect}"
