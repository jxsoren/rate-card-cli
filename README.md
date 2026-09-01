# rate-card

Interactive CLI that generates a shipping rate card — a weight × zone grid of rates — from the
**eHub production API**. Prints the card to your terminal and saves CSVs to `~/Downloads`.

## Install

```bash
bundle install
```

Ruby 3.3.4 (pinned in `.ruby-version`).

The TUI is [bubbletea-ruby](https://github.com/marcoroth/bubbletea-ruby) with `bubbles` and
`lipgloss`. These ship precompiled native binaries, so no Go toolchain is needed to install
them. Note that `bubbles` is a shared gem name — `0.0.x` is an unrelated gem that pulls in
`aws-sdk` — which is why the Gemfile pins `~> 0.1`.

## Use

```bash
bundle exec exe/rate-card
```

No flags needed — the wizard asks for everything:

1. **eHub API token** — pasted, masked. Decoded so you can confirm the account before the run
   starts. Never written to disk. A malformed token re-prompts rather than ending the run.
2. **Carrier**, then **services** — the list comes from the customer's own service catalogue
   (`GET /api/v2/services?category=shipping`), so it is exactly what that customer has enabled,
   including services that would not quote at a single probe weight.
3. **Zones** (`1-8`, or `1,3,5`), **weight unit** (`oz`/`lbs`), **weight range**,
   **package type**, **rate columns** (shipper rate, meter rate).
4. A recap of every answer, with the call count, and a confirm. Enter alone declines —
   only `y` starts a run. Declining does nothing at all.

Bad input at the zone or weight prompt re-prompts; it never costs you the run.

### Keys

| Key | Effect |
| --- | --- |
| `↑` / `↓`, `k` / `j` | Move between choices |
| `space` | Tick or untick (services, rate columns) |
| `a` | Tick or untick everything |
| `enter` | Confirm the answer |
| `ctrl-c` | Abandon the run at any point |

Answered questions stay on screen as you go, and the fetch shows a live bar with a running
count of failed cells — so a run that is going wrong can be abandoned early rather than waited
out.

### One caveat: paste only the token

The token prompt is deliberately a plain readline **before** the TUI starts, because
bubbletea-ruby 0.1.4's input reader returns one key per poll and discards the rest of the
buffered bytes: a pasted 200-character JWT arrives as a single character. Typing is unaffected
at any speed, so every other answer is safe inside the TUI — but **type** the zone and weight
ranges rather than pasting them. `spike/burst_probe.rb` reproduces the underlying bug.

For a bare `rate-card` command:

```bash
ln -s "$PWD/exe/rate-card" ~/bin/rate-card
```

### Flags

| Flag | Effect |
| --- | --- |
| `--output-dir DIR` | Save CSVs somewhere other than `~/Downloads/rate_cards` |
| `--no-table` | Skip printing tables to stdout |
| `--version`, `--help` | As expected |

Everything else is interactive by design — a second input path would let flags and wizard
answers disagree.

## Output

Both to your terminal and to disk:

```
  ops@acme.test (1042) · USPS Ground Advantage · shipper rate
┌────────┬──────┬──────┬──────┬──────┬──────┬──────┬──────┬──────┐
│ wt(oz) │   Z1 │   Z2 │   Z3 │   Z4 │   Z5 │   Z6 │   Z7 │   Z8 │
├────────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
│      1 │ 3.25 │ 3.50 │ 3.75 │ 4.00 │ 4.25 │ 4.50 │ 4.75 │ 5.00 │
│      2 │ 4.75 │ 5.00 │ 5.25 │ 5.50 │    — │ 6.00 │ 6.25 │ 6.50 │
└────────┴──────┴──────┴──────┴──────┴──────┴──────┴──────┴──────┘

  ⚠ 1 cell failed
      wt 2  Z5  → 500 upstream carrier error

  ✓ Saved 2 files to ~/Downloads/rate_cards/ops_acme_test_1042_2026-09-01T12-00-00Z
      GroundAdvantage_shipper_rate.csv
      GroundAdvantage_meter_rate.csv
```

One CSV per service per rate column. Header is `weight` plus one column per zone. The run
directory is timestamped, so a new card never clobbers an old one.

**A missing rate is an empty cell, never `0.00`.** A zero in a rate table reads as a genuine
free rate; `../rate_table_builder` writes `0.0` there and this tool deliberately does not.
Failures are listed after the tables with weight, zone and reason, and a run with holes still
writes its files.

## Call volume

One API call per (weight × zone). **Services are free**: one response carries every service the
customer has enabled, so checking six costs the same as one. A 16-weight, 8-zone card is 128
calls, fanned out 8 at a time.

Two distinct no-output cases, which the tool does not conflate:

- **Every call failed** → likely network or token.
- **Calls succeeded but nothing was priced** → your service, package type or weight range.
  USPS First Class is not quoted above 13 oz, for instance.

A carrier failure is not a failed call: eHub answers 201 and puts the reason in the response
`warnings` array, or in a service's `errors` field. Both are reported under
*the API reported N warnings*, deduplicated with an occurrence count.

## Tests

```bash
bundle exec rspec
```

**No test contacts production** — `Client` is the only network seam, and specs stub it via
Faraday's test adapter.

## Design

The wizard's only product is a validated `RunSpec`; everything downstream consumes only that.
So the fetch/assemble/render engine is testable with no prompting and no network.

| File | Responsibility |
| --- | --- |
| `exe/rate-card` | Entrypoint: flags → wizard → runner. Every error becomes one clean line |
| `client.rb` | The only network seam. Every outcome becomes a Hash, `Unauthorized`, or `RequestFailed` |
| `token.rb` | Decodes the JWT payload to name the account. Does not verify the signature |
| `service_catalog.rb` | Service catalogue response → `Service` objects, grouped by carrier |
| `run_spec.rb` | The validated inputs for one run |
| `shipment.rb` | One (weight, zone) request payload |
| `grid.rb` | Fans out the calls, assembles cells and failures |
| `csv_writer.rb` / `table_renderer.rb` | Peers reading the same `Grid`, so files and terminal cannot disagree |
| `ui.rb` | Every byte the tool prints |
| `wizard.rb` / `runner.rb` | Ask; then orchestrate |

`constants/addresses.rb` holds hand-verified zone addresses — zone membership is a property of
a real address and a carrier's zone chart, so it is never derived at runtime.

## Related tools

- `../rate_sheet_builder` — batch, multi-customer, YAML roster. Use it for many customers at once.
- `../rate_table_builder` — the abandoned predecessor to this tool.

## Not done

`spec/fixtures/rates_response.json` was never captured, so no test pins the production response
field names (`service_rates`, `service_id`, `rate`, `meter_rate`, `errors`). If eHub renames one, the tool
will produce empty cells rather than failing loudly. Capturing one real response would close
that gap — see Task 16 of `docs/superpowers/plans/2026-08-31-rate-card-cli.md`.
