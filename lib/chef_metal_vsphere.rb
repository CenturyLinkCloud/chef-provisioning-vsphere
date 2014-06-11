require 'chef_metal'
require 'chef_metal_vsphere/vsphere_driver'

class Chef
  module DSL
    module Recipe
      def with_vsphere_driver(driver_options = nil, &block)
      	url, config = VsphereDriver.canonicalize_url(nil, {:driver_options => driver_options})
  		with_driver url, config, &block
      end
    end
  end
end