# rate-card

Interactive CLI that generates a shipping rate card — a weight × zone grid of rates — from the
**eHub production API**. Prints the card to your terminal and saves CSVs to `~/Downloads`.

## Install

Copy and run this. You do not need Ruby, or anything else, installed first:

```bash
cd ~ && brew install jxsoren/tools/rate-card
```

Then run it:

```bash
rate-card
```

Homebrew installs its own Ruby and keeps every dependency inside the keg, so this cannot
collide with an rbenv, asdf or system Ruby you already have.

<details>
<summary>Don't have Homebrew?</summary>

Install it first — this asks for your Mac password and takes a few minutes:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Follow the "Next steps" it prints at the end, then run the install command above.
</details>

If you already work in Ruby, the gem is equivalent:

```bash
gem install rate-card
```

## Update

New versions are not delivered automatically, and the tool will not tell you one exists.
When a new version is announced:

```bash
cd ~ && brew update && brew upgrade rate-card
```

`brew update` is what tells your machine a new version exists — Homebrew only checks for
itself once every 24 hours, so without it `brew upgrade` may report nothing to do.

Check what you are on with `rate-card --version`, and what is current at
[rubygems.org/gems/rate-card](https://rubygems.org/gems/rate-card).

## Uninstall

```bash
brew uninstall rate-card
```

## If the install or update fails

**`The current working directory must exist to run brew`** — your terminal is sitting in a
folder that has since been deleted or renamed. `cd ~` fixes it, which is why the commands
above start with it. Confirm it is not this tool by running `brew --version`; it fails the
same way.

**`No available formula with the name "rate-card"`** — the tap part of the name is missing.
Use the full `jxsoren/tools/rate-card`, not just `rate-card`.

**`command not found: rate-card`** after a successful install — open a new terminal so it
picks up Homebrew's PATH.

Anything else: send the full output.

## Develop

```bash
bundle install
bundle exec exe/rate-card
NO_COLOR=1 bundle exec rspec
```

`NO_COLOR=1` is required when running the specs from a terminal — five specs assert on
uncoloured rendered output, and lipgloss colours whenever stdout is a tty. See the comment
in `spec/spec_helper.rb`.

Ruby 3.3.4 (pinned in `.ruby-version`); the gemspec floor is 3.2, and Homebrew currently
builds against Ruby 4.0.

The TUI is [bubbletea-ruby](https://github.com/marcoroth/bubbletea-ruby) with `bubbles` and
`lipgloss`. These ship precompiled native binaries, so no Go toolchain is needed to install
them. Note that `bubbles` is a shared gem name — `0.0.x` is an unrelated gem that pulls in
`aws-sdk` — which is why the gemspec pins `~> 0.1`.

## Release

Commits to `main` do not reach users. `brew install` serves the published gem, so everyone
stays on the last released version until you cut a new one. The only input is the version.

One-time setup:

```bash
gh repo clone jxsoren/homebrew-tools ~/homebrew-tools
```

Per release — bump `lib/rate_card/version.rb`, commit, then:

```bash
bin/release --dry-run    # optional: everything except the two publishing steps
bin/release
```

That runs preflight (clean tree, version not already published, tag free, tap clean and
up to date), runs the specs, builds the gem, pushes it to RubyGems, rewrites the formula's
`url` and `sha256` to the checksum of the exact file pushed, commits and tags here, and
commits and pushes the formula to the tap. No manual steps.

Preflight runs before anything is published because a release cannot be undone — RubyGems
refuses to re-push a version even after a yank. If a step *after* the gem push fails, the
gem is already public: re-run the formula steps by hand rather than bumping the version.

Versioning: bug fix `0.1.1`, new feature `0.2.0`, breaking change to flags or output
`1.0.0`. Users upgrade with `brew update && brew upgrade rate-card`.

`packaging/homebrew/rate-card.rb` is the source of truth for the formula; the tap's
`Formula/rate-card.rb` is a copy written by `bin/release`.

## Use

```bash
bundle exec exe/rate-card
```

No flags needed — the wizard asks for everything:

1. **Provider** — announced, not yet asked: eHub is the only one built so
   far. Printed before the token prompt so the run says what it targets
   before a production credential is pasted into it.
2. **eHub API token** — pasted, masked. Decoded so you can confirm the account before the run
   starts. Never written to disk. A malformed token re-prompts rather than ending the run.
3. **Rate by** — Weight or Cubic dimensions. Only asked when the token has USPS
   services, since USPS cubic pricing (Ground Advantage Cubic, Priority Mail Cubic) is
   priced by which of ten official volume tiers the package falls into, not by weight.
   Choosing Cubic restricts the carrier to USPS and replaces the weight-unit and
   weight-range questions with a multi-select of the ten tiers. Choosing Cubic does not check
   that the service you go on to pick is actually cubic-priced — you're responsible for
   selecting a cubic-rated USPS service (e.g. "USPS Ground Advantage Cubic").
4. **Carrier**, then **services** — the list comes from the customer's own service catalogue
   (`GET /api/v2/services?category=shipping`), so it is exactly what that customer has enabled,
   including services that would not quote at a single probe weight.
5. **Zones** (`1-8`, or `1,3,5`); then, in weight mode, **weight unit** (`oz`/`lbs`) and
   **weight range** — or, in cubic mode, the **cubic tiers** to include; then
   **package type**, **rate columns** (shipper rate, meter rate).
6. A recap of every answer, with the call count, and a **Run** / **Back** choice. It opens on
   **Back**, so a stray enter carried over from the previous question goes back rather than
   spending 128 production calls; `ctrl-c` abandons the session outright.

Bad input at the zone or weight prompt re-prompts; it never costs you the run.

`esc` steps back to the previous question at any point in the wizard, including from the recap.
The question you land on reopens on the answer it already has; the answers that came *after* it
are forgotten, since they were given against a choice you are about to change.

### Keys

| Key | Effect |
| --- | --- |
| `↑` / `↓`, `k` / `j` | Move between choices |
| `space` | Tick or untick (services, rate columns) |
| `a` | Tick or untick everything |
| `enter` | Confirm the answer |
| `esc` | Go back to the previous question |
| `ctrl-c` | Abandon the run at any point |

Answered questions stay on screen as you go, and the fetch shows a live bar with a running
count of failed cells — so a run that is going wrong can be abandoned early rather than waited
out.

### One caveat: paste only the token

The token prompt is deliberately a plain readline **before** the TUI starts, because
bubbletea-ruby 0.1.4's input reader returns one key per poll and discards the rest of the
buffered bytes: a pasted 200-character JWT arrives as a single character. Typing is unaffected
at any speed, so every other answer is safe inside the TUI — but **type** the zone and weight
ranges rather than pasting them.

To reproduce the underlying bug: run a bare Bubbletea model that logs every `KeyMessage`, then
write 36 bytes to its pty in one call. One message arrives, carrying one rune; the other 35
bytes are discarded.

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
│      1 │ 1.11 │ 2.22 │ 3.33 │ 4.44 │ 5.55 │ 6.66 │ 7.77 │ 8.88 │
│      2 │ 2.11 │ 3.22 │ 4.33 │ 5.44 │    — │ 7.66 │ 8.77 │ 9.88 │
└────────┴──────┴──────┴──────┴──────┴──────┴──────┴──────┴──────┘

  ⚠ 1 cell failed
      wt 2  Z5  → 500 upstream carrier error

  ✓ Saved 2 files to ~/Downloads/rate_cards/ops_acme_test_1042_2026-09-01T12-00-00Z
      GroundAdvantage_shipper_rate.csv
      GroundAdvantage_meter_rate.csv
```

The rates above are invented placeholders, not a real quote.

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
NO_COLOR=1 bundle exec rspec
```

**No test contacts production** — `Client` is the only network seam, and specs stub it via
Faraday's test adapter.

## Design

The wizard's only product is a validated `RunSpec`; everything downstream consumes only that.
So the fetch/assemble/render engine is testable with no prompting and no network.

| File | Responsibility |
| --- | --- |
| `exe/rate-card` | Entrypoint: flags → wizard → runner. Every error becomes one clean line |
| `providers.rb` | Registry mapping a provider key to the object that builds it |
| `providers/ehub/provider.rb` | Implements the provider interface for eHub: auth, catalogue parsing, request/response shape |
| `providers/ehub/client.rb` | The only network seam. Every outcome becomes a Hash, `Unauthorized`, or `RequestFailed` |
| `providers/ehub/token.rb` | Decodes the JWT payload to name the account. Does not verify the signature |
| `providers/ehub/service_catalog.rb` | Service catalogue response → `Service` objects, grouped by carrier |
| `run_spec.rb` | The validated inputs for one run |
| `providers/ehub/shipment.rb` | One (weight, zone) request payload |
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
