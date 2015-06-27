require 'rbvmomi'

module ChefProvisioningVsphere
  class VsphereHelper

    if !$guest_op_managers
      $guest_op_managers = {}
    end

    def initialize(connect_options, datacenter_name)
      @connect_options = connect_options
      @datacenter_name = datacenter_name
    end

    attr_reader :connect_options
    attr_reader :datacenter_name

    def vim
      if @current_connection.nil? or @current_connection.serviceContent.sessionManager.currentSession.nil?
        puts "establishing connection to #{connect_options[:host]}"
        @current_connection = RbVmomi::VIM.connect connect_options
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

    def find_vm(folder, vm_name)
      folder = find_folder(folder) unless folder.is_a? RbVmomi::VIM::Folder
      folder.find(vm_name, RbVmomi::VIM::VirtualMachine)
    end

    def find_vm_by_id(uuid)
      vm = vim.searchIndex.FindByUuid(
        uuid: uuid,
        vmSearch: true,
        instanceUuid: true
      )
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

    #folder could be like:  /Level1/Level2/folder_name
    def find_folder(folder_name)
      base = datacenter.vmFolder
      unless folder_name.nil?
        folder_name.split('/').reject(&:empty?).each do |item|
          base = base.find(item, RbVmomi::VIM::Folder) ||
            raise("vSphere Folder not found [#{folder_name}]")
        end
      end
      base
    end

    def datacenter
      @datacenter ||= vim.serviceInstance.find_datacenter(datacenter_name) ||
        raise("vSphere Datacenter not found [#{datacenter_name}]")
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
        backing_info.deviceName
      end
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
      action_handler.report_progress('finding networks...')
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

    def find_entity(name, parent_folder, &block)
      parts = name.split('/').reject(&:empty?)
      parts.each do |item|
        Chef::Log.debug("Identifying entity part: #{item} in folder type: #{parent_folder.class}")
        if parent_folder.is_a? RbVmomi::VIM::Folder
          Chef::Log.debug('Parent folder is a folder')
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

      if host.is_a?(RbVmomi::VIM::ComputeResource)
        host = host.host.first
      end
      host
    end

    def find_pool(pool_name)
      Chef::Log.debug("Finding pool: #{pool_name}")
      pool = find_entity(pool_name, datacenter.hostFolder) do |parent, part|
        case parent
        when RbVmomi::VIM::ClusterComputeResource, RbVmomi::VIM::ComputeResource
          Chef::Log.debug("finding #{part} in a #{parent.class}: #{parent.name}")
          Chef::Log.debug("Parent root pool has #{parent.resourcePool.resourcePool.count} pools")
          parent.resourcePool.resourcePool.each { |p| Chef::Log.debug(p.name ) }
          parent.resourcePool.resourcePool.find { |f| f.name == part }
        when RbVmomi::VIM::ResourcePool
          Chef::Log.debug("finding #{part} in a Resource Pool: #{parent.name}")
          Chef::Log.debug("Pool has #{parent.resourcePool.count} pools")
          parent.resourcePool.each { |p| Chef::Log.debug(p.name ) }
          parent.resourcePool.find { |f| f.name == part }
        else
          Chef::Log.debug("parent of #{part} is unexpected type: #{parent.class}")
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
          base = base.find(item)
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
