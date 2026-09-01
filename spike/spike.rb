require 'bubbletea'
require 'bubbles'

Tick = Struct.new(:n)
class Done < Bubbletea::Message; end
class Progressed < Bubbletea::Message
  attr_reader :n
  def initialize(n) = @n = n
end

TOTAL = 40

class Spike
  include Bubbletea::Model
  def initialize(done: 0, finished: false)
    @done = done
    @finished = finished
    @bar = Bubbles::Progress.new(width: 40)
  end

  def init
    # background "HTTP" work in a Proc command -> runs in Thread.new
    cmd = lambda do
      TOTAL.times do |i|
        sleep 0.01
        $runner.send(Progressed.new(i + 1))   # push from worker thread
      end
      Done.new
    end
    [self, cmd]
  end

  def update(message)
    case message
    when Progressed then @done = message.n
    when Done       then return [self, Bubbletea.quit]
    end
    [self, nil]
  end

  def view
    pct = @done.to_f / TOTAL
    "  fetching\n  #{@bar.view_as(pct)}  #{@done}/#{TOTAL}\n"
  end
end

runner = Bubbletea::Runner.new(Spike.new)
$runner = runner
runner.run
puts "\nEXIT OK final=#{TOTAL}"
