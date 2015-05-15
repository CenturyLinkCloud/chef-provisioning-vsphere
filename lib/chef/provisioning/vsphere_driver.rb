require 'chef/provisioning'
require 'chef/provisioning/vsphere_driver/driver'

class Chef
  module DSL
    module Recipe
      def with_vsphere_driver(driver_options, &block)
        url = ChefProvisioningVsphere::VsphereDriver.canonicalize_url(
          nil, driver_options)[0]
        with_driver url, driver_options, &block
      end
    end
  end
end
