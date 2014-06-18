require 'rbvmomi'

module ChefMetalVsphere
  module Helpers

    def vim(options = connect_options)
      # reconnect on every call - connections may silently timeout during long operations (e.g. cloning)
      RbVmomi::VIM.connect options
    end

    def find_vm(dc_name, vm_folder, vm_name)
      folder = find_folder(dc_name, vm_folder) or raise("vSphere Folder not found [#{vm_folder}] for vm #{vm_name}")
      vm     = folder.find(vm_name, RbVmomi::VIM::VirtualMachine)
    end

    def find_vm_by_id(uuid, connection = vim)
      vm = connection.searchIndex.FindByUuid({:uuid => uuid, :vmSearch => true, :instanceUuid => true})
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
      if folder_name && folder_name.length > 0
        entityArray = folder_name.split('/')
        entityArray.each do |entityArrItem|
          if entityArrItem != ''
            baseEntity = baseEntity.childEntity.grep(RbVmomi::VIM::Folder).find { |f| f.name == entityArrItem }
          end
        end
      end
      baseEntity
    end

    def dc(dc_name)
      vim.serviceInstance.find_datacenter(dc_name) or raise("vSphere Datacenter not found [#{datacenter}]")
    end

    def do_vm_clone(dc_name, vm_template, vm_name, options)
      datacenter = dc(dc_name)
      if options.has_key?(:host)
        host = find_host(datacenter, options[:host])
        rspec = RbVmomi::VIM.VirtualMachineRelocateSpec(host: host) 
      else
        pool = options[:resource_pool] ? find_pool(datacenter, options[:resource_pool]) : vm_template.resourcePool
        rspec = RbVmomi::VIM.VirtualMachineRelocateSpec(pool: pool)
        raise 'either :host or :resource_pool must be specified when cloning from a VM Template' if pool.nil?
      end

      unless options[:datastore].to_s.empty?
        rspec.datastore = find_datastore(datacenter, options[:datastore])
      end

      clone_spec = RbVmomi::VIM.VirtualMachineCloneSpec(
        location: rspec,
        powerOn: false,
        template: false
      )

      clone_spec.config = RbVmomi::VIM.VirtualMachineConfigSpec(:deviceChange => Array.new)

      if options.has_key?(:customization_spec)
        if(options[:customization_spec].is_a?(Hash))
            cust_options = options[:customization_spec]
            raise ArgumentError, "domain is required" unless cust_options.key?(:domain)
            if cust_options.key?(:ipsettings)
              raise ArgumentError, "ip and subnetMask is required for static ip" unless cust_options[:ipsettings].key?(:ip) and
                                                                                        cust_options[:ipsettings].key?(:subnetMask)
              cust_ip_settings = RbVmomi::VIM::CustomizationIPSettings.new(cust_options[:ipsettings])
              cust_ip_settings.ip = RbVmomi::VIM::CustomizationFixedIp(:ipAddress => cust_options[:ipsettings][:ip])
            end
            cust_domain = cust_options[:domain]
            cust_ip_settings ||= RbVmomi::VIM::CustomizationIPSettings.new(:ip => RbVmomi::VIM::CustomizationDhcpIpGenerator.new())
            cust_ip_settings.dnsDomain = cust_domain
            cust_global_ip_settings = RbVmomi::VIM::CustomizationGlobalIPSettings.new
            cust_global_ip_settings.dnsServerList = cust_ip_settings.dnsServerList
            cust_global_ip_settings.dnsSuffixList = [cust_domain]
            cust_hostname = RbVmomi::VIM::CustomizationFixedName.new(:name => cust_options[:hostname]) if cust_options.key?(:hostname)
            cust_hostname ||= RbVmomi::VIM::CustomizationFixedName.new(:name => vm_name)
            cust_hwclockutc = cust_options[:hw_clock_utc]
            cust_timezone = cust_options[:time_zone]
            cust_prep = RbVmomi::VIM::CustomizationLinuxPrep.new(
              :domain => cust_domain,
              :hostName => cust_hostname,
              :hwClockUTC => cust_hwclockutc,
              :timeZone => cust_timezone)
            cust_adapter_mapping = [RbVmomi::VIM::CustomizationAdapterMapping.new(:adapter => cust_ip_settings)]
            cust_spec = RbVmomi::VIM::CustomizationSpec.new(
              :identity => cust_prep,
              :globalIPSettings => cust_global_ip_settings,
              :nicSettingMap => cust_adapter_mapping)
        else
          cust_spec = find_customization_spec(options[:customization_spec])
        end
        clone_spec.customization = cust_spec
      end

      unless options[:annotation].to_s.nil?
        clone_spec.config.annotation = options[:annotation]
      end

      unless options[:num_cpus].to_s.nil?
        clone_spec.config.numCPUs = options[:num_cpus]
      end

      unless options[:memory_mb].to_s.nil?
        clone_spec.config.memoryMB = options[:memory_mb]
      end

      unless options[:network_name].to_s.nil?
        config_spec_operation = RbVmomi::VIM::VirtualDeviceConfigSpecOperation('edit')
        nic_backing_info = RbVmomi::VIM::VirtualEthernetCardNetworkBackingInfo(:deviceName => options[:network_name])
        connectable = RbVmomi::VIM::VirtualDeviceConnectInfo(
          :allowGuestControl => true,
          :connected => true,
          :startConnected => true)
        device = RbVmomi::VIM::VirtualE1000(
          :backing => nic_backing_info,
          :deviceInfo => RbVmomi::VIM::Description(:label => "Network adapter 1", :summary => options[:network_name]),
          :key => 4000,
          :connectable => connectable)
        device_spec = RbVmomi::VIM::VirtualDeviceConfigSpec(
          :operation => config_spec_operation,
          :device => device)

        clone_spec.config.deviceChange.push device_spec
      end

      vm_template.CloneVM_Task(
        name: vm_name,
        folder: find_folder(dc_name, options[:vm_folder]),
        spec: clone_spec
      ).wait_for_completion

    vm = find_vm(dc_name, options[:vm_folder], vm_name)

    unless options[:additional_disk_size_gb].to_s.nil?
      if options[:datastore].to_s.empty? 
        raise ":datastore must be specified when adding a disk to a cloned vm"
      end
      idx = vm.disks.count
      task = vm.ReconfigVM_Task(:spec => RbVmomi::VIM.VirtualMachineConfigSpec(:deviceChange =>[RbVmomi::VIM::VirtualDeviceConfigSpec(
            :operation     => :add,
            :fileOperation => :create,
            :device        => RbVmomi::VIM.VirtualDisk(
              :key           => idx,
              :backing       => RbVmomi::VIM.VirtualDiskFlatVer2BackingInfo(
                :fileName        => "[#{options[:datastore]}]",
                :diskMode        => 'persistent',
                :thinProvisioned => true
              ),
              :capacityInKB  => options[:additional_disk_size_gb] * 1024 * 1024,
              :controllerKey => 1000,
              :unitNumber    => idx
            )
      )]))
      task.wait_for_completion
    end

    vm
    end

    def find_datastore(dc, datastore_name)
        baseEntity = dc.datastore
        baseEntity.find { |f| f.info.name == datastore_name } or raise "no such datastore #{datastore_name}"    
    end

    def find_host(dc, host_name)
      baseEntity = dc.hostFolder
      entityArray = host_name.split('/')
      entityArray.each do |entityArrItem|
        if entityArrItem != ''
          if baseEntity.is_a? RbVmomi::VIM::Folder
            baseEntity = baseEntity.childEntity.find { |f| f.name == entityArrItem } or nil
          elsif baseEntity.is_a? RbVmomi::VIM::ClusterComputeResource or baseEntity.is_a? RbVmomi::VIM::ComputeResource
            baseEntity = baseEntity.host.find { |f| f.name == entityArrItem } or nil
          elsif baseEntity.is_a? RbVmomi::VIM::HostSystem
            baseEntity = baseEntity.host.find { |f| f.name == entityArrItem } or nil
          else
            baseEntity = nil
          end
        end
      end

      raise "vSphere Host not found [#{host_name}]" if baseEntity.nil?

      baseEntity = baseEntity.host if not baseEntity.is_a?(RbVmomi::VIM::HostSystem) and baseEntity.respond_to?(:host)
      baseEntity
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
