require 'chef_metal'
require 'chef_metal_vsphere/vsphere_provisioner'

class Chef
  module DSL
    module Recipe
      def with_vsphere_provisioner(options = {}, &block)
        run_context.chef_metal.with_provisioner(ChefMetalVsphere::VsphereProvisioner.new(options), &block)
      end
    end
  end
end