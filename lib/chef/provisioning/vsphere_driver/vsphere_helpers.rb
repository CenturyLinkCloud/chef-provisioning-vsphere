require 'rbvmomi'

module ChefProvisioningVsphere
  module Helpers

    if !$guest_op_managers
      $guest_op_managers = {}
    end

    def vim(options = connect_options)
      if @current_connection.nil? or @current_connection.serviceContent.sessionManager.currentSession.nil?
        puts "establishing connection to #{options[:host]}"
        @current_connection = RbVmomi::VIM.connect options
        str_conn = @current_connection.pretty_inspect # a string in the format of VIM(host ip)
        
        # we are caching guest operation managers in a global variable...terrible i know
        # this object is available from the serviceContent object on API version 5 forward
        # Its a singleton and if another connection is made for the same host and user
        # that object is not available on any subsequent connection
        # I could find no documentation that discusses this
        if !$guest_op_managers.has_key?(str_conn)
          $guest_op_managers[str_conn] = @current_connection.serviceContent.guestOperationsManager
        end
      end

      @current_connection
    end

    def find_vm(vm_folder, vm_name)
      folder = find_folder(vm_folder) ||
        raise("vSphere Folder not found [#{vm_folder}] for vm #{vm_name}")
      vm     = folder.find(vm_name, RbVmomi::VIM::VirtualMachine)
    end

    def find_vm_by_id(uuid, connection = vim)
      vm = connection.searchIndex.FindByUuid(
        uuid: uuid,
        vmSearch: true,
        instanceUuid: true
      )
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
    def find_folder(folder_name)
      base = datacenter.vmFolder
      if folder_name && folder_name.length > 0
        entityArray = folder_name.split('/').reject(&:empty?)
        entityArray.each do |item|
          base = base.childEntity.grep(RbVmomi::VIM::Folder).find do |f|
            f.name == item
          end
        end
      end
      base
    end

    def datacenter
      dc_name = config[:machine_options][:bootstrap_options][:datacenter]
      @datacenter ||= vim.serviceInstance.find_datacenter(dc_name) ||
        raise("vSphere Datacenter not found [#{dc_name}]")
    end

    def network_adapter_for(operation, network_name, network_label, device_key, backing_info)
      connectable = RbVmomi::VIM::VirtualDeviceConnectInfo(
        :allowGuestControl => true,
        :connected => true,
        :startConnected => true)
      device = RbVmomi::VIM::VirtualVmxnet3(
        :backing => backing_info,
        :deviceInfo => RbVmomi::VIM::Description(:label => network_label, :summary => network_name.split('/').last),
        :key => device_key,
        :connectable => connectable)
      RbVmomi::VIM::VirtualDeviceConfigSpec(
        :operation => operation,
        :device => device)
    end

    def find_ethernet_cards_for(vm)
      vm.config.hardware.device.select {|d| d.is_a?(RbVmomi::VIM::VirtualEthernetCard)}
    end

    def do_vm_clone(action_handler, vm_template, vm_name, options)
      deviceAdditions = []

      clone_spec = RbVmomi::VIM.VirtualMachineCloneSpec(
        location: relocate_spec_for(vm_template, options),
        powerOn: false,
        template: false,
        config: RbVmomi::VIM.VirtualMachineConfigSpec(
          :cpuHotAddEnabled => true,
          :memoryHotAddEnabled => true,
          :cpuHotRemoveEnabled => true,
          :deviceChange => Array.new)
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
        folder: find_folder(options[:vm_folder]),
        spec: clone_spec
      ).wait_for_completion

      vm = find_vm(options[:vm_folder], vm_name)

      if options[:additional_disk_size_gb].to_i > 0
        task = vm.ReconfigVM_Task(:spec => RbVmomi::VIM.VirtualMachineConfigSpec(:deviceChange => [virtual_disk_for(vm, options)]))
        task.wait_for_completion
      end

      vm
    end

    def add_extra_nic(action_handler, vm_template, options, vm)
      deviceAdditions, changes = network_device_changes(action_handler, vm_template, options)

      if deviceAdditions.count > 0
        current_networks = find_ethernet_cards_for(vm).map{|card| network_id_for(card.backing)}
        new_devices = deviceAdditions.select { |device| !current_networks.include?(network_id_for(device.device.backing))}
        
        if new_devices.count > 0
          action_handler.report_progress "Adding extra NICs"
          task = vm.ReconfigVM_Task(:spec => RbVmomi::VIM.VirtualMachineConfigSpec(:deviceChange => new_devices))
          task.wait_for_completion
          new_devices
        end
      end
    end

    def network_id_for(backing_info)
      if backing_info.is_a?(RbVmomi::VIM::VirtualEthernetCardDistributedVirtualPortBackingInfo)
        backing_info.port.portgroupKey
      else
        backing_info.network
      end
    end

    def relocate_spec_for(vm_template, options)
      if options.has_key?(:host)
        host = find_host(options[:host])
        rspec = RbVmomi::VIM.VirtualMachineRelocateSpec(host: host) 
      else
        pool = options[:resource_pool] ? find_pool(options[:resource_pool]) : vm_template.resourcePool
        rspec = RbVmomi::VIM.VirtualMachineRelocateSpec(pool: pool)
        raise 'either :host or :resource_pool must be specified when cloning from a VM Template' if pool.nil?
      end

      if options.has_key?(:use_linked_clone)
        create_delta_disk(vm_template)
        rspec.diskMoveType = :moveChildMostDiskBacking
      end

      unless options[:datastore].to_s.empty?
        rspec.datastore = find_datastore(options[:datastore])
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
        raise ':datastore must be specified when adding a disk to a cloned vm'
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
        backing_info = backing_info_for(action_handler, networks[i])
        if card = cards.shift
          key = card.key
          operation = RbVmomi::VIM::VirtualDeviceConfigSpecOperation('edit')
          action_handler.report_progress "changing template nic for #{networks[i]}"
          changes.push(
            network_adapter_for(operation, networks[i], label, key, backing_info))
        else
          key = key + 1
          operation = RbVmomi::VIM::VirtualDeviceConfigSpecOperation('add')
          action_handler.report_progress "will be adding nic for #{networks[i]}"
          additions.push(
            network_adapter_for(operation, networks[i], label, key, backing_info))
        end
      end
      [additions, changes]
    end

    def backing_info_for(action_handler, network_name)
      network = find_network(network_name)
      action_handler.report_progress(
        "network: #{network_name} is a #{network.class}")
      if network.is_a?(RbVmomi::VIM::DistributedVirtualPortgroup)
        port = RbVmomi::VIM::DistributedVirtualSwitchPortConnection(
          :switchUuid => network.config.distributedVirtualSwitch.uuid,
          :portgroupKey => network.key
        )
        RbVmomi::VIM::VirtualEthernetCardDistributedVirtualPortBackingInfo(
          :port => port)
      else
        RbVmomi::VIM::VirtualEthernetCardNetworkBackingInfo(
          deviceName: network_name.split('/').last)
      end
    end

    def find_datastore(datastore_name)
      datacenter.datastore.find { |f| f.info.name == datastore_name } or raise "no such datastore #{datastore_name}"
    end

    def customization_options_from(action_handler, vm_template, vm_name, options)
      if options.has_key?(:customization_spec)
        if(options[:customization_spec].is_a?(Hash))
          cust_options = options[:customization_spec]
          ip_settings = cust_options[:ipsettings]
          cust_domain = cust_options[:domain]

          raise ArgumentError, 'domain is required' unless cust_domain
          cust_ip_settings = nil
          if ip_settings && ip_settings.key?(:ip)
            unless cust_options[:ipsettings].key?(:subnetMask)
              raise ArgumentError, 'subnetMask is required for static ip'
            end
            cust_ip_settings = RbVmomi::VIM::CustomizationIPSettings.new(ip_settings)
            action_handler.report_progress "customizing #{vm_name} with static IP #{ip_settings[:ip]}"
            cust_ip_settings.ip = RbVmomi::VIM::CustomizationFixedIp(:ipAddress => ip_settings[:ip])
          end
          if cust_ip_settings.nil?
            cust_ip_settings= RbVmomi::VIM::CustomizationIPSettings.new(:ip => RbVmomi::VIM::CustomizationDhcpIpGenerator.new())
            cust_ip_settings.dnsServerList = ip_settings[:dnsServerList]
            action_handler.report_progress "customizing #{vm_name} with dynamic IP and DNS: #{ip_settings[:dnsServerList]}"
          end

          cust_ip_settings.dnsDomain = cust_domain
          cust_global_ip_settings = RbVmomi::VIM::CustomizationGlobalIPSettings.new
          cust_global_ip_settings.dnsServerList = cust_ip_settings.dnsServerList
          cust_global_ip_settings.dnsSuffixList = [cust_domain]
          cust_hostname = hostname_from(cust_options, vm_name)
          cust_hwclockutc = cust_options[:hw_clock_utc]
          cust_timezone = cust_options[:time_zone]

          if vm_template.config.guestId.start_with?('win')
            cust_prep = windows_prep_for(action_handler, options, vm_name)
          else
            cust_prep = RbVmomi::VIM::CustomizationLinuxPrep.new(
              :domain => cust_domain,
              :hostName => cust_hostname,
              :hwClockUTC => cust_hwclockutc,
              :timeZone => cust_timezone
            )
          end
          cust_adapter_mapping = [RbVmomi::VIM::CustomizationAdapterMapping.new(:adapter => cust_ip_settings)]
          RbVmomi::VIM::CustomizationSpec.new(
            :identity => cust_prep,
            :globalIPSettings => cust_global_ip_settings,
            :nicSettingMap => cust_adapter_mapping
          )
        else
          find_customization_spec(cust_options)
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
          :value => ENV['domainAdminPassword'] || cust_options[:domainAdminPassword])
        cust_id = RbVmomi::VIM::CustomizationIdentification.new(
          :joinDomain => cust_options[:domain],
          :domainAdmin => cust_options[:domainAdmin],
          :domainAdminPassword => cust_domain_password)
        #puts "my env passwd is: #{ENV['domainAdminPassword']}"
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

    def find_entity(name, parent_folder, &block)
      parts = name.split('/').reject(&:empty?)
      parts.each do |item|
        if parent_folder.is_a? RbVmomi::VIM::Folder
          parent_folder = parent_folder.childEntity.find { |f| f.name == item }
        else
          parent_folder = block.call(parent_folder, item)
        end
      end
      parent_folder
    end

    def find_host(host_name)
      host = find_entity(host_name, datacenter.hostFolder) do |parent, part|
        case parent
        when RbVmomi::VIM::ClusterComputeResource || RbVmomi::VIM::ComputeResource
          parent.host.find { |f| f.name == part }
        when RbVmomi::VIM::HostSystem
          parent.host.find { |f| f.name == part }
        else
          nil
        end
      end

      raise "vSphere Host not found [#{host_name}]" if host.nil?

      if !host.is_a?(RbVmomi::VIM::HostSystem) && host.respond_to?(:host)
        host = host.host
      end
      host
    end

    def find_pool(pool_name)
      pool = find_entity(pool_name, datacenter.hostFolder) do |parent, part|
        case parent
        when RbVmomi::VIM::ClusterComputeResource || RbVmomi::VIM::ComputeResource
          parent.resourcePool.resourcePool.find { |f| f.name == part }
        when RbVmomi::VIM::ResourcePool
          parent.resourcePool.find { |f| f.name == part }
        else
          nil
        end
      end

      raise "vSphere ResourcePool not found [#{pool_name}]" if pool.nil?

      if !pool.is_a?(RbVmomi::VIM::ResourcePool) && pool.respond_to?(:resourcePool)
        pool = pool.resourcePool
      end
      pool
    end

    def find_network(name)
      base = datacenter.networkFolder
      entity_array = name.split('/').reject(&:empty?)
      entity_array.each do |item|
        case base
        when RbVmomi::VIM::Folder
          base = base.childEntity.find { |f| f.name == item }
        when RbVmomi::VIM::VmwareDistributedVirtualSwitch
          idx = base.summary.portgroupName.find_index(item)
          base = idx.nil? ? nil : base.portgroup[idx]
        end
      end

      raise "vSphere Network not found [#{name}]" if base.nil?

      base
    end

    def find_customization_spec(customization_spec)
      csm = vim.serviceContent.customizationSpecManager
      csi = csm.GetCustomizationSpec(:name => customization_spec)
      spec = csi.spec
      raise "Customization Spec not found [#{customization_spec}]" if spec.nil?
      spec
    end

    def upload_file_to_vm(vm, username, password, local, remote)
      auth = RbVmomi::VIM::NamePasswordAuthentication({:username => username, :password => password, :interactiveSession => false})
      size = File.size(local)
      endpoint = $guest_op_managers[vim.pretty_inspect].fileManager.InitiateFileTransferToGuest(
        :vm => vm, 
        :auth => auth, 
        :guestFilePath => remote,
        :overwrite => true,
        :fileAttributes => RbVmomi::VIM::GuestWindowsFileAttributes.new,
        :fileSize => size)

        uri = URI.parse(endpoint)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        
        req = Net::HTTP::Put.new("#{uri.path}?#{uri.query}")
        req.body_stream = File.open(local)
        req["Content-Type"] = "application/octet-stream"
        req["Content-Length"] = size
        res = http.request(req) 
        unless res.kind_of?(Net::HTTPSuccess)
          raise "Error: #{res.inspect} :: #{res.body} :: sending #{local} to #{remote} at #{vm.name} via #{endpoint} with a size of #{size}"
        end
    end
  end
end
