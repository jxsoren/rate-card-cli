require 'bubbletea'
class Bump < Bubbletea::Message; end
class Fin  < Bubbletea::Message; end
N = 2000
class M
  include Bubbletea::Model
  def initialize = @seen = 0
  def init
    [self, lambda {
      threads = 4.times.map { Thread.new { (N/4).times { $r.send(Bump.new) } } }
      threads.each(&:join)
      sleep 0.5
      Fin.new
    }]
  end
  def update(m)
    case m
    when Bump then @seen += 1
    when Fin  then $seen = @seen; return [self, Bubbletea.quit]
    end
    [self, nil]
  end
  def view = "seen #{@seen}"
end
$r = Bubbletea::Runner.new(M.new)
begin
  $r.run
rescue => e
  $err = "#{e.class}: #{e.message}"
end
puts "\nRESULT sent=#{N} received=#{$seen.inspect} err=#{$err.inspect}"
