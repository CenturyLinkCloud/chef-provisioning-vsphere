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

    def network_adapter_for(operation, network_name, network_label, device_key)
        nic_backing_info = RbVmomi::VIM::VirtualEthernetCardNetworkBackingInfo(:deviceName => network_name)
        connectable = RbVmomi::VIM::VirtualDeviceConnectInfo(
          :allowGuestControl => true,
          :connected => true,
          :startConnected => true)
        device = RbVmomi::VIM::VirtualVmxnet3(
          :backing => nic_backing_info,
          :deviceInfo => RbVmomi::VIM::Description(:label => network_label, :summary => network_name),
          :key => device_key,
          :connectable => connectable)
        RbVmomi::VIM::VirtualDeviceConfigSpec(
          :operation => operation,
          :device => device)
    end

    def find_ethernet_cards_for(vm)
      vm.config.hardware.device.select {|d| d.is_a?(RbVmomi::VIM::VirtualEthernetCard)}
    end

    def do_vm_clone(action_handler, dc_name, vm_template, vm_name, options)
      deviceAdditions = []

      clone_spec = RbVmomi::VIM.VirtualMachineCloneSpec(
        location: relocate_spec_for(dc_name, vm_template, options),
        powerOn: false,
        template: false,
        config: RbVmomi::VIM.VirtualMachineConfigSpec(:deviceChange => Array.new)
      )

      clone_spec.customization = customization_options_from(action_handler, vm_template, vm_name, options)

      unless options[:annotation].to_s.nil?
        clone_spec.config.annotation = options[:annotation]
      end

      unless options[:num_cpus].to_s.nil?
        clone_spec.config.numCPUs = options[:num_cpus]
      end

      unless options[:memory_mb].to_s.nil?
        clone_spec.config.memoryMB = options[:memory_mb]
      end

      unless options[:network_name].nil?
        deviceAdditions, changes = network_device_changes(action_handler, vm_template, options)
        clone_spec.config.deviceChange = changes
      end

      vm_template.CloneVM_Task(
        name: vm_name,
        folder: find_folder(dc_name, options[:vm_folder]),
        spec: clone_spec
      ).wait_for_completion

      vm = find_vm(dc_name, options[:vm_folder], vm_name)

      unless options[:additional_disk_size_gb].nil?
        task = vm.ReconfigVM_Task(:spec => RbVmomi::VIM.VirtualMachineConfigSpec(:deviceChange => [virtual_disk_for(vm, options)]))
        task.wait_for_completion
      end

      vm
    end

    def add_extra_nic(action_handler, vm_template, options, vm)
      deviceAdditions, changes = network_device_changes(action_handler, vm_template, options)

      if deviceAdditions.count > 0
        current_networks = find_ethernet_cards_for(vm).map{|card| card.backing.deviceName}
        new_devices = deviceAdditions.select { |device| !current_networks.include?(device.device.backing.deviceName)}
        
        if new_devices.count > 0
          action_handler.report_progress "Adding extra NICs"
          task = vm.ReconfigVM_Task(:spec => RbVmomi::VIM.VirtualMachineConfigSpec(:deviceChange => new_devices))
          task.wait_for_completion
          new_devices
        end
      end
    end

    def relocate_spec_for(dc_name, vm_template, options)
      datacenter = dc(dc_name)
      if options.has_key?(:host)
        host = find_host(datacenter, options[:host])
        rspec = RbVmomi::VIM.VirtualMachineRelocateSpec(host: host) 
      else
        pool = options[:resource_pool] ? find_pool(datacenter, options[:resource_pool]) : vm_template.resourcePool
        rspec = RbVmomi::VIM.VirtualMachineRelocateSpec(pool: pool)
        raise 'either :host or :resource_pool must be specified when cloning from a VM Template' if pool.nil?
      end

      if options.has_key?(:use_linked_clone)
        create_delta_disk(vm_template)
        rspec.diskMoveType = :moveChildMostDiskBacking
      else
        unless options[:datastore].to_s.empty?
          rspec.datastore = find_datastore(datacenter, options[:datastore])
        end
      end

      rspec
    end

    def create_delta_disk(vm_template)
        disks = vm_template.config.hardware.device.grep(RbVmomi::VIM::VirtualDisk)
        disks.select { |disk| disk.backing.parent == nil }.each do |disk|
          spec = {
              :deviceChange => [
                  {
                      :operation => :remove,
                      :device => disk
                  },
                  {
                      :operation => :add,
                      :fileOperation => :create,
                      :device => disk.dup.tap { |new_disk|
                        new_disk.backing = new_disk.backing.dup
                        new_disk.backing.fileName = "[#{disk.backing.datastore.name}]"
                        new_disk.backing.parent = disk.backing
                      },
                  }
              ]
          }
          vm_template.ReconfigVM_Task(:spec => spec).wait_for_completion
          end
      end

    def virtual_disk_for(vm, options)
      if options[:datastore].to_s.empty? 
        raise ":datastore must be specified when adding a disk to a cloned vm"
      end
      idx = vm.disks.count
      RbVmomi::VIM::VirtualDeviceConfigSpec(
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
      )
    end

    def network_device_changes(action_handler, vm_template, options)
      additions = []
      changes = []
      networks=options[:network_name]
      if networks.kind_of?(String)
        networks=[networks]
      end

      cards = find_ethernet_cards_for(vm_template)

      key = 4000
      networks.each_index do | i |
        label = "Ethernet #{i+1}"
        if card = cards.shift
          key = card.key
          operation = RbVmomi::VIM::VirtualDeviceConfigSpecOperation('edit')
          action_handler.report_progress "changing template nic for #{networks[i]}"
          changes.push(
            network_adapter_for(operation, networks[i], label, key))
        else
          key = key + 1
          operation = RbVmomi::VIM::VirtualDeviceConfigSpecOperation('add')
          action_handler.report_progress "will be adding nic for #{networks[i]}"
          additions.push(
            network_adapter_for(operation, networks[i], label, key))
        end
      end
      [additions, changes]
    end

    def find_datastore(dc, datastore_name)
        baseEntity = dc.datastore
        baseEntity.find { |f| f.info.name == datastore_name } or raise "no such datastore #{datastore_name}"    
    end

    def customization_options_from(action_handler, vm_template, vm_name, options)
      if options.has_key?(:customization_spec)
        if(options[:customization_spec].is_a?(Hash))
            cust_options = options[:customization_spec]
            raise ArgumentError, "domain is required" unless cust_options.key?(:domain)
            cust_ip_settings = nil
            if cust_options.key?(:ipsettings) and cust_options[:ipsettings].key?(:ip)
              raise ArgumentError, "ip and subnetMask is required for static ip" unless cust_options[:ipsettings].key?(:ip) and
                                                                                        cust_options[:ipsettings].key?(:subnetMask)
              cust_ip_settings = RbVmomi::VIM::CustomizationIPSettings.new(cust_options[:ipsettings])
              action_handler.report_progress "customizing #{vm_name} with static IP #{cust_options[:ipsettings][:ip]}"
              cust_ip_settings.ip = RbVmomi::VIM::CustomizationFixedIp(:ipAddress => cust_options[:ipsettings][:ip])
            end
            cust_domain = cust_options[:domain]
            if cust_ip_settings.nil?
              action_handler.report_progress "customizing #{vm_name} with dynamic IP"
              cust_ip_settings= RbVmomi::VIM::CustomizationIPSettings.new(:ip => RbVmomi::VIM::CustomizationDhcpIpGenerator.new())
            end

            cust_ip_settings.dnsDomain = cust_domain
            cust_global_ip_settings = RbVmomi::VIM::CustomizationGlobalIPSettings.new
            cust_global_ip_settings.dnsServerList = cust_ip_settings.dnsServerList
            cust_global_ip_settings.dnsSuffixList = [cust_domain]
            cust_hostname = hostname_from(options[:customization_spec], vm_name)
            cust_hwclockutc = cust_options[:hw_clock_utc]
            cust_timezone = cust_options[:time_zone]

            if vm_template.config.guestId.start_with?('win')
              cust_prep = windows_prep_for(action_handler, options, vm_name)
            else
              cust_prep = RbVmomi::VIM::CustomizationLinuxPrep.new(
                :domain => cust_domain,
                :hostName => cust_hostname,
                :hwClockUTC => cust_hwclockutc,
                :timeZone => cust_timezone)
            end
              cust_adapter_mapping = [RbVmomi::VIM::CustomizationAdapterMapping.new(:adapter => cust_ip_settings)]
              RbVmomi::VIM::CustomizationSpec.new(
                :identity => cust_prep,
                :globalIPSettings => cust_global_ip_settings,
                :nicSettingMap => cust_adapter_mapping)
        else
          find_customization_spec(options[:customization_spec])
        end
      end
    end

    def windows_prep_for(action_handler, options, vm_name)
      cust_options = options[:customization_spec]
      cust_runonce = RbVmomi::VIM::CustomizationGuiRunOnce.new(
        :commandList => [
          'winrm set winrm/config/client/auth @{Basic="true"}',
          'winrm set winrm/config/service/auth @{Basic="true"}',
          'winrm set winrm/config/service @{AllowUnencrypted="true"}',
          'shutdown -l'])

      cust_login_password = RbVmomi::VIM::CustomizationPassword(
        :plainText => true,
        :value => options[:ssh][:password])
      if cust_options.has_key?(:domain) and cust_options[:domain] != 'local'
        cust_domain_password = RbVmomi::VIM::CustomizationPassword(
          :plainText => true,
          :value => cust_options[:domainAdminPassword])
        cust_id = RbVmomi::VIM::CustomizationIdentification.new(
          :joinDomain => cust_options[:domain],
          :domainAdmin => cust_options[:domainAdmin],
          :domainAdminPassword => cust_domain_password)
        action_handler.report_progress "joining domain #{cust_options[:domain]} with user: #{cust_options[:domainAdmin]}"
      else
        cust_id = RbVmomi::VIM::CustomizationIdentification.new(
          :joinWorkgroup => 'WORKGROUP')
      end
      cust_gui_unattended = RbVmomi::VIM::CustomizationGuiUnattended.new(
        :autoLogon => true,
        :autoLogonCount => 1,
        :password => cust_login_password,
        :timeZone => cust_options[:win_time_zone])
      cust_userdata = RbVmomi::VIM::CustomizationUserData.new(
        :computerName => hostname_from(cust_options, vm_name),
        :fullName => cust_options[:org_name],
        :orgName => cust_options[:org_name],
        :productId => cust_options[:product_id])
      RbVmomi::VIM::CustomizationSysprep.new(
        :guiRunOnce => cust_runonce,
        :identification => cust_id,
        :guiUnattended => cust_gui_unattended,
        :userData => cust_userdata)
    end

    def hostname_from(options, vm_name)
      if options.key?(:hostname)
        RbVmomi::VIM::CustomizationFixedName.new(:name => options[:hostname])
      else
        RbVmomi::VIM::CustomizationFixedName.new(:name => vm_name)
      end
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
