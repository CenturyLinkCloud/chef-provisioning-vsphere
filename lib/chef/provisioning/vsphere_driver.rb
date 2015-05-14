require 'chef/provisioning'
require 'chef/provisioning/vsphere_driver/driver'

class Chef
  module DSL
    module Recipe
      def with_vsphere_driver(driver_options, &block)
        options = { driver_options: driver_options }
        url = ChefProvisioningVsphere::VsphereDriver.canonicalize_url(
          nil, options)[0]
        with_driver url, options, &block
      end
    end
  end
end
