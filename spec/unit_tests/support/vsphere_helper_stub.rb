module ChefProvisioningVsphereStubs
  class VsphereHelperStub < ChefProvisioningVsphere::VsphereHelper
    def initialize
    end

    def network_device_changes(action_handler, vm_template, options)
      [
        [RbVmomi::VIM::VirtualDeviceConfigSpec.new],
        [RbVmomi::VIM::VirtualDeviceConfigSpec.new]
      ]
    end

    def find_host(host_name)
      RbVmomi::VIM::HostSystem.new
    end

    def find_pool(pool_name)
      RbVmomi::VIM::ResourcePool.new(nil, nil)
    end

    def find_datastore(datastore_name)
      RbVmomi::VIM::Datastore.new
    end

    def find_customization_spec(options)
      RbVmomi::VIM::CustomizationSpec.new
    end

    def create_delta_disk(vm_template)
    end
  end
end

module RbVmomi
  class VIM::HostSystem
    attr_reader :parent

    def parent
      @parent ||= RbVmomi::VIM::ComputeResource.new
    end
  end
end

module RbVmomi
  class VIM::ComputeResource
    attr_reader :resourcePool

    def resourcePool
      @resourcePool ||= RbVmomi::VIM::ResourcePool.new(nil, nil)
    end
  end
end
