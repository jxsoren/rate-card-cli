# frozen_string_literal: true

module RateCard
  module Constants
    # Maps known eHub service ids to a carrier name, so the wizard can group the
    # live-discovered service list. Ids sourced from
    # ../rate_table_builder/constants/service_constants.rb. An unknown id is
    # grouped under 'Other' rather than dropped — the customer really does have
    # it enabled, we just do not recognise it.
    module Carriers
      OTHER = 'Other'

      SERVICE_CARRIERS = {
        # USPS
        683 => 'USPS', 684 => 'USPS', 689 => 'USPS', 690 => 'USPS',
        691 => 'USPS', 692 => 'USPS', 1172 => 'USPS',
        # FedEx
        392 => 'FedEx', 393 => 'FedEx', 394 => 'FedEx',
        395 => 'FedEx', 396 => 'FedEx', 398 => 'FedEx'
      }.freeze

      DISPLAY_ORDER = ['USPS', 'UPS', 'FedEx', 'DHL', 'Amazon', OTHER].freeze

      module_function

      def for_service_id(id)
        SERVICE_CARRIERS.fetch(id.to_i, OTHER)
      end

      def display_order
        DISPLAY_ORDER
      end
    end
  end
end
