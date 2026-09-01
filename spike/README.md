# spike

Throwaway probes kept as evidence for decisions in the Bubbletea migration.

| File | What it shows |
| --- | --- |
| `spike.rb` | A background `Proc` command driving a progress bar — the pattern the fetch uses |
| `race.rb` | `Runner#send` has no mutex; 2000 messages from 4 threads, no drops on CRuby |
| `burst_probe.rb` | The paste bug: a 36-byte atomic write yields one KeyMessage with one rune |
| `live_check.rb` | The real TUI end to end against a fake API |
| `drive.rb` | Drives `live_check.rb` under a pty. `P:` prefixes an atomic write (a paste) |

```bash
TOKEN=$(bundle exec ruby -rbase64 -rjson -e 'e=->(h){Base64.urlsafe_encode64(JSON.generate(h),padding:false)}; print "#{e.({alg:"none"})}.#{e.({data:{user:{customer_id:1042,email:"ops@acme.test"}}})}.sig"')
KEYS="P:$TOKEN
|SP|CR|1-3|CR|CR|1-4|CR|CR|CR|y" bundle exec ruby spike/drive.rb
```
