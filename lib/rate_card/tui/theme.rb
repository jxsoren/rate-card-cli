# frozen_string_literal: true

require 'lipgloss'

module RateCard
  module TUI
    # Every colour and glyph the TUI uses. Lipgloss strips colour by itself when
    # stdout is not a terminal, so nothing here needs a tty? guard — unlike the
    # Pastel/TTY pairing this replaced, where only Pastel was gated and the
    # spinner and bar leaked escapes into a pipe.
    module Theme
      ACCENT  = Lipgloss::AdaptiveColor.new(dark: '#00D3FF', light: '#0072B5')
      OK      = Lipgloss::AdaptiveColor.new(dark: '#2ECC71', light: '#1E8449')
      WARNING = Lipgloss::AdaptiveColor.new(dark: '#F5A623', light: '#B7791F')
      DANGER  = Lipgloss::AdaptiveColor.new(dark: '#FF5C5C', light: '#C0392B')
      MUTED   = Lipgloss::AdaptiveColor.new(dark: '#8A8A8A', light: '#6B6B6B')

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
