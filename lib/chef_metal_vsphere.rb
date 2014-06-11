require 'chef_metal'
require 'chef_metal_vsphere/vsphere_driver'

class Chef
  module DSL
    module Recipe
      def with_vsphere_driver(driver_options = nil, &block)
      	url = VsphereDriver.canonicalize_url({:driver_options => driver_options})
  		with_driver url, driver_options, &block
      end
    end
  end
end