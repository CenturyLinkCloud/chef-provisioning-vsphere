require 'chef/provisioning'
require 'chef/provisioning/vsphere_driver/driver'

class Chef
  module DSL
    module Recipe
      def with_vsphere_driver(driver_options, &block)
      	url, config = ChefProvisioningVsphere::VsphereDriver.canonicalize_url(nil, {:driver_options => driver_options})
  		with_driver url, driver_options, &block
      end
    end
  end
end