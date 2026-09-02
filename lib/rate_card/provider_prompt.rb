# frozen_string_literal: true

module RateCard
  # The one thing printed before the credential prompt, so the run says which
  # provider it targets before anything is pasted into it. Selecting among
  # more than one registered provider is not implemented yet, so more than one
  # key raises rather than silently choosing the first.
  module ProviderPrompt
    module_function

    def read(ui:, keys: Providers.all)
      raise ArgumentError, 'multi-provider selection is not implemented yet' if keys.length > 1

      key = keys.first
      ui.info("Provider: #{Providers.build(key).label}")
      key
    end
  end
end
