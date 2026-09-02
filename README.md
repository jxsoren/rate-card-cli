# rate-card

Interactive CLI that generates a shipping rate card — a weight × zone grid of rates — from the
eHub production API. Prints the card to your terminal and saves CSVs to `~/Downloads`.

## Install

```bash
cd ~ && brew install jxsoren/tools/rate-card
```

Then run it:

```bash
rate-card
```

If you already work in Ruby, the gem is equivalent:

```bash
gem install rate-card
```

## Update

```bash
cd ~ && brew update && brew upgrade rate-card
```

## Uninstall

```bash
brew uninstall rate-card
```
