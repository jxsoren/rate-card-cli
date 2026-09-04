# frozen_string_literal: true

require 'lipgloss'
require 'bubbles'

module RateCard
  module TUI
    # Every colour and glyph the TUI uses. Lipgloss strips colour by itself when
    # stdout is not a terminal, so nothing here needs a tty? guard — unlike the
    # Pastel/TTY pairing this replaced, where only Pastel was gated and the
    # spinner and bar leaked escapes into a pipe.
    module Theme
      ACCENT    = Lipgloss::AdaptiveColor.new(dark: '#00D3FF', light: '#0072B5')
      SECONDARY = Lipgloss::AdaptiveColor.new(dark: '#B388FF', light: '#6A3FBF')
      OK        = Lipgloss::AdaptiveColor.new(dark: '#2ECC71', light: '#1E8449')
      WARNING   = Lipgloss::AdaptiveColor.new(dark: '#F5A623', light: '#B7791F')
      DANGER    = Lipgloss::AdaptiveColor.new(dark: '#FF5C5C', light: '#C0392B')
      MUTED     = Lipgloss::AdaptiveColor.new(dark: '#8A8A8A', light: '#6B6B6B')

      CURSOR      = '❯'
      CHECKED     = '◉'
      UNCHECKED   = '○'
      TICK        = '✓'
      CROSS       = '✗'
      BULLET      = '▸'
      ALERT       = '⚠'

      # The canonical Charm keybinding legend (bubbles/help) instead of a
      # hand-built "a · b · c" string — it colours the key apart from its
      # description and truncates to width on its own rather than wrapping
      # mid-word in a narrow terminal.
      HELP = Bubbles::Help.new.tap do |help|
        help.key_style = Lipgloss::Style.new.foreground(ACCENT).bold(true)
        help.desc_style = Lipgloss::Style.new.foreground(MUTED)
        help.separator_style = Lipgloss::Style.new.foreground(MUTED)
      end

      module_function

      def style = Lipgloss::Style.new

      def accent(text)  = style.foreground(ACCENT).render(text)
      def ok(text)      = style.foreground(OK).render(text)
      def warning(text) = style.foreground(WARNING).render(text)
      def danger(text)  = style.foreground(DANGER).render(text)
      def muted(text)   = style.foreground(MUTED).render(text)
      def bold(text)    = style.bold(true).render(text)

      # Section/scenario headings use SECONDARY rather than ACCENT so they
      # read as structure, not as something the cursor is sitting on — ACCENT
      # is reserved for the interactive element the user's eye should track.
      def title(text)
        style.bold(true).foreground(SECONDARY).render(text)
      end

      # The run targets production and cannot be pointed elsewhere, so the
      # banner says so in the one colour the eye catches first.
      def banner
        style.border(Lipgloss::ROUNDED_BORDER)
             .border_foreground(ACCENT)
             .padding(0, 1)
             .render("#{bold('eHub Rate Card Builder')}\n#{danger('●')} production · api.ehub.com")
      end

      # Frames the live wizard body (transcript + current field) as one card
      # instead of loose scrolling text, so every stage reads as part of the
      # same surface rather than a fresh block of terminal output.
      def panel(content)
        style.border(Lipgloss::ROUNDED_BORDER)
             .border_foreground(MUTED)
             .padding(1, 2)
             .render(content)
      end

      # A quiet rule between the answered-questions transcript and whatever
      # is being asked right now, so the eye has a fixed place to land on
      # "what's next" without re-reading everything above it.
      def divider(width = 44)
        muted('─' * width)
      end

      # Renders a row of Bubbles::Key::Binding as the short help legend.
      def help_view(bindings)
        HELP.short_help_view(bindings)
      end

      # Drawn once, below the panel, instead of every field repeating its own
      # keybinding line — the keys on offer rarely change shape from field to
      # field, so giving them a fixed home lets the eye stop re-reading them.
      def footer(text)
        "  #{text}"
      end
    end
  end
end
