# frozen_string_literal: true

require 'lipgloss'

module RateCard
  module TUI
    # Every colour and glyph the TUI uses. Lipgloss strips colour by itself when
    # stdout is not a terminal, so nothing here needs a tty? guard — unlike the
    # Pastel/TTY pairing this replaced, where only Pastel was gated and the
    # spinner and bar leaked escapes into a pipe.
    module Theme
      ACCENT  = '39'  # cyan
      OK      = '42'  # green
      WARNING = '214' # amber
      DANGER  = '203' # red
      MUTED   = '244' # grey

      CURSOR      = '❯'
      CHECKED     = '◉'
      UNCHECKED   = '○'
      TICK        = '✓'
      CROSS       = '✗'
      BULLET      = '▸'
      ALERT       = '⚠'

      module_function

      def style = Lipgloss::Style.new

      def accent(text)  = style.foreground(ACCENT).render(text)
      def ok(text)      = style.foreground(OK).render(text)
      def warning(text) = style.foreground(WARNING).render(text)
      def danger(text)  = style.foreground(DANGER).render(text)
      def muted(text)   = style.foreground(MUTED).render(text)
      def bold(text)    = style.bold(true).render(text)

      def title(text)
        style.bold(true).foreground(ACCENT).render(text)
      end

      # The run targets production and cannot be pointed elsewhere, so the
      # banner says so in the one colour the eye catches first.
      def banner
        style.border(Lipgloss::ROUNDED_BORDER)
             .border_foreground(ACCENT)
             .padding(0, 1)
             .render("#{bold('eHub Rate Card Builder')}\n#{danger('●')} production · api.ehub.com")
      end
    end
  end
end
