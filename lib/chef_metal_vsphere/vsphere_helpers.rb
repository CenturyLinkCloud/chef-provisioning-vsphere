module ChefMetalVsphere
  module Helpers

    def vim
      # reconnect on every call - connections may silently timeout during long operations (e.g. cloning)
      conn_opts = {
        :host => connect_options['vsphere_host'],
        :port => connect_options['vsphere_port'],
        :path => connect_options['vshere_path'],
        :use_ssl => connect_options['vsphere_ssl'],
        :insecure => connect_options['vsphere_insecure'],
        :proxyHost => connect_options['proxy_host'],
        :proxyPort => connect_options['proxy_port'],
        :user => connect_options['vsphere_user'],
        :password => connect_options['vsphere_password']
      }

      vim = RbVmomi::VIM.connect conn_opts
      return vim
    end

    def find_vm(dc_name, vm_folder, vm_name)
      folder = find_folder(dc_name, vm_folder) or raise("vSphere Folder not found [#{vm_folder}] for vm #{vm_name}")
      vm     = folder.find(vm_name, RbVmomi::VIM::VirtualMachine)
    end

    def vm_started?(vm, wait_on_port = 22)
      return false if vm.nil?
      state = vm.runtime.powerState
      return false unless state == 'poweredOn'
      return false unless port_ready?(vm, wait_on_port)
      return true
    end

    def vm_stopped?(vm)
      return true if vm.nil?
      state = vm.runtime.powerState
      return false unless state == 'poweredOff'
      return false
    end

    def start_vm(vm, wait_on_port = 22)
      state = vm.runtime.powerState
      unless state == 'poweredOn'
        vm.PowerOnVM_Task.wait_for_completion
      end

      sleep 1 until port_ready?(vm, wait_on_port)
    end

    def stop_vm(vm)
      begin
        vm.ShutdownGuest
        sleep 2 until vm.runtime.powerState == 'poweredOff'
      rescue
        vm.PowerOffVM_Task.wait_for_completion
      end
    end

    def port_ready?(vm, port)
      vm_ip = vm.guest.ipAddress
      return false if vm_ip.nil?

      begin
        tcp_socket = TCPSocket.new(vm_ip, port)
        readable = IO.select([tcp_socket], nil, nil, 5)
        if readable
          true
        else
          false
        end
      rescue Errno::ETIMEDOUT
        false
      rescue Errno::EPERM
        false
      rescue Errno::ECONNREFUSED
        false
      rescue Errno::EHOSTUNREACH, Errno::ENETUNREACH
        false
      ensure
        tcp_socket && tcp_socket.close
      end
    end

    #folder could be like:  /Level1/Level2/folder_name
    def find_folder(dc_name, folder_name)
      #dc(dc_name).vmFolder.childEntity.grep(RbVmomi::VIM::Folder).find { |x| x.name == folder_name }
      baseEntity = dc(dc_name).vmFolder
      entityArray = folder_name.split('/')
      entityArray.each do |entityArrItem|
        if entityArrItem != ''
          baseEntity = baseEntity.childEntity.grep(RbVmomi::VIM::Folder).find { |f| f.name == entityArrItem }
        end
      end
      baseEntity
    end

    def dc(dc_name)
      vim.serviceInstance.find_datacenter(dc_name) or raise("vSphere Datacenter not found [#{datacenter}]")
    end

    def do_vm_clone(dc_name, vm_template, vm_name, options)
      pool = options['resource_pool'] ? find_pool(dc(dc_name), options['resource_pool']) : vm_template.resourcePool
      raise ':resource_pool must be specified when cloning from a VM Template' if pool.nil?

      clone_spec = RbVmomi::VIM.VirtualMachineCloneSpec(
        location: RbVmomi::VIM.VirtualMachineRelocateSpec(pool: pool),
        powerOn: false,
        template: false
      )

      clone_spec.config = RbVmomi::VIM.VirtualMachineConfigSpec(:deviceChange => Array.new)

      unless options['customization_spec'].to_s.empty?
        clone_spec.customization = find_customization_spec(options['customization_spec'])
      end

      unless options['annotation'].to_s.nil?
        clone_spec.config.annotation = options['annotation']
      end

      unless options['num_cpus'].to_s.nil?
        clone_spec.config.numCPUs = options['num_cpus']
      end

      unless options['memory_mb'].to_s.nil?
        clone_spec.config.memoryMB = options['memory_mb']
      end

      vm_template.CloneVM_Task(
        name: vm_name,
        folder: find_folder(dc_name, options['vm_folder']),
        spec: clone_spec
      ).wait_for_completion
    end

    def find_pool(dc, pool_name)
      baseEntity = dc.hostFolder
      entityArray = pool_name.split('/')
      entityArray.each do |entityArrItem|
        if entityArrItem != ''
          if baseEntity.is_a? RbVmomi::VIM::Folder
            baseEntity = baseEntity.childEntity.find { |f| f.name == entityArrItem } or nil
          elsif baseEntity.is_a? RbVmomi::VIM::ClusterComputeResource or baseEntity.is_a? RbVmomi::VIM::ComputeResource
            baseEntity = baseEntity.resourcePool.resourcePool.find { |f| f.name == entityArrItem } or nil
          elsif baseEntity.is_a? RbVmomi::VIM::ResourcePool
            baseEntity = baseEntity.resourcePool.find { |f| f.name == entityArrItem } or nil
          else
            baseEntity = nil
          end
        end
      end

      raise "vSphere ResourcePool not found [#{pool_name}]" if baseEntity.nil?

      baseEntity = baseEntity.resourcePool if not baseEntity.is_a?(RbVmomi::VIM::ResourcePool) and baseEntity.respond_to?(:resourcePool)
      baseEntity
    end

    def find_customization_spec(customization_spec)
      csm = vim.serviceContent.customizationSpecManager
      csi = csm.GetCustomizationSpec(:name => customization_spec)
      spec = csi.spec
      raise "Customization Spec not found [#{customization_spec}]" if spec.nil?
      spec
    end
  end
end
