require 'pty'
out = +''
pid = nil
PTY.spawn({ 'TERM' => 'xterm-256color' }, 'bundle exec ruby spike/live_check.rb') do |r, w, child|
  pid = child
  reader = Thread.new { loop { out << r.readpartial(4096) } rescue nil }
  # 'P:' prefix means one atomic write, i.e. a paste. Everything else is typed
  # a character at a time, which is what a human does.
  ENV.fetch('KEYS').split('|').each do |chunk|
    sleep 0.4
    if chunk.start_with?('P:')
      w.write(chunk.delete_prefix('P:'))
      next
    end
    text = chunk == 'CR' ? "\r" : (chunk == 'SP' ? ' ' : chunk)
    text.each_char { |c| w.write(c); sleep 0.01 }
  end
  # Hard deadline: a stalled TUI must fail the check, not hang it.
  deadline = Time.now + 8
  sleep 0.2 while Time.now < deadline && !out.include?('LIVE:')
  Process.kill('KILL', child) rescue nil
  Process.wait(child) rescue nil
  reader.kill
end
clean = out.gsub(/\e\[[0-9;?]*[a-zA-Z]/, '').gsub(/\e[()][B0]/, '').gsub(/\e[=>]/, '')
puts clean
puts(out.include?('LIVE:') ? '### COMPLETED' : '### STALLED')
