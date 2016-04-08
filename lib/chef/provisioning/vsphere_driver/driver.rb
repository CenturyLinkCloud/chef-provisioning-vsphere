require 'chef'
require 'cheffish/merged_config'
require 'chef/provisioning/driver'
require 'chef/provisioning/machine/windows_machine'
require 'chef/provisioning/machine/unix_machine'
require 'chef/provisioning/vsphere_driver/clone_spec_builder'
require 'chef/provisioning/vsphere_driver/version'
require 'chef/provisioning/vsphere_driver/vsphere_helpers'
require 'chef/provisioning/vsphere_driver/vsphere_url'

module ChefProvisioningVsphere
  # Provisions machines in vSphere.
  class VsphereDriver < Chef::Provisioning::Driver
    include Chef::Mixin::ShellOut

    def self.from_url(driver_url, config)
      VsphereDriver.new(driver_url, config)
    end

    # Create a new Vsphere provisioner.
    #
    # ## Parameters
    # connect_options - hash of options to be passed to RbVmomi::VIM.connect
    #   :host       - required - hostname of the vSphere API server
    #   :port       - optional - port on the vSphere API server (default: 443)
    #   :path        - optional - path on the vSphere API server (default: /sdk)
    #   :use_ssl        - optional - true to use ssl in connection to vSphere API server (default: true)
    #   :insecure   - optional - true to ignore ssl certificate validation errors in connection to vSphere API server (default: false)
    #   :user       - required - user name to use in connection to vSphere API server
    #   :password   - required - password to use in connection to vSphere API server
    def self.canonicalize_url(driver_url, config)
      config = symbolize_keys(config)
      [ driver_url || URI::VsphereUrl.from_config(config).to_s, config ]
    end

    def self.symbolize_keys(h)
      Hash === h ?
        Hash[
          h.map do |k, v|
            [k.respond_to?(:to_sym) ? k.to_sym : k, symbolize_keys(v)]
          end
        ] : h
    end

    def initialize(driver_url, config)
      super(driver_url, config)

      uri = URI(driver_url)
      @connect_options = {
        provider: 'vsphere',
        host: uri.host,
        port: uri.port,
        use_ssl: uri.use_ssl,
        insecure: uri.insecure,
        path: uri.path
      }

      if driver_options
        @connect_options[:user] = driver_options[:user]
        @connect_options[:password] = driver_options[:password]
      end
    end

    attr_reader :connect_options

    # Acquire a machine, generally by provisioning it.  Returns a Machine
    # object pointing at the machine, allowing useful actions like setup,
    # converge, execute, file and directory.  The Machine object will have a
    # "node" property which must be saved to the server (if it is any
    # different from the original node object).
    #
    # ## Parameters
    # action_handler - the action_handler object that is calling this method; this
    #        is generally a action_handler, but could be anything that can support the
    #        ChefMetal::ActionHandler interface (i.e., in the case of the test
    #        kitchen metal driver for acquiring and destroying VMs; see the base
    #        class for what needs providing).
    # node - node object (deserialized json) representing this machine.  If
    #        the node has a provisioner_options hash in it, these will be used
    #        instead of options provided by the provisioner.  TODO compare and
    #        fail if different?
    #        node will have node['normal']['provisioner_options'] in it with any options.
    #        It is a hash with this format:
    #
    #           -- provisioner_url: vsphere://host:port?ssl=[true|false]&insecure=[true|false]
    #           -- bootstrap_options: hash of options to pass to RbVmomi::VIM::VirtualMachine::CloneTask()
    #                :datacenter
    #                :resource_pool
    #                :cluster
    #                :datastore
    #                :template_name
    #                :template_folder
    #                :vm_folder
    #                :winrm {...} (not yet implemented)
    #                :ssh {...}
    #
    #        Example bootstrap_options for vSphere:
    #          TODO: add other CloneTask params, e.g.: datastore, annotation, resource_pool, ...
    #          'bootstrap_options' => {
    #            'template_name' =>'centos6.small',
    #            'template_folder' =>'Templates',
    #            'vm_folder' => 'MyApp'
    #          }
    #
    #        node['normal']['provisioner_output'] will be populated with information
    #        about the created machine.  For vSphere, it is a hash with this
    #        format:
    #
    #           -- provisioner_url: vsphere:host:port?ssl=[true|false]&insecure=[true|false]
    #           -- vm_folder: name of the vSphere folder containing the VM
    #
    def allocate_machine(action_handler, machine_spec, machine_options)
      merge_options! machine_options

      if machine_spec.location
        Chef::Log.warn(
          "Checking to see if #{machine_spec.location} has been created...")
        vm = vm_for(machine_spec)
        if vm
          Chef::Log.warn 'returning existing machine'
          return vm
        else
          Chef::Log.warn machine_msg(
            machine_spec.name,
            machine_spec.location['server_id'],
            'no longer exists.  Recreating ...'
          )
        end
      end
      bootstrap_options = machine_options[:bootstrap_options]

      action_handler.report_progress full_description(
        machine_spec, bootstrap_options)

      vm = find_or_create_vm(bootstrap_options, machine_spec, action_handler)

      add_machine_spec_location(vm, machine_spec)

      action_handler.performed_action(machine_msg(
        machine_spec.name,
        vm.config.instanceUuid,
        'created'
      ))
      vm
    end

    def merge_options!(machine_options)
      @config = Cheffish::MergedConfig.new(
        { machine_options: machine_options },
        @config
      )
    end

    def add_machine_spec_location(vm, machine_spec)
      machine_spec.location = {
        'driver_url' => driver_url,
        'driver_version' => VERSION,
        'server_id' => vm.config.instanceUuid,
        'is_windows' => is_windows?(vm),
        'allocated_at' => Time.now.utc.to_s,
        'ipaddress' => vm.guest.ipAddress
      }
    end

    def find_or_create_vm(bootstrap_options, machine_spec, action_handler)
      vm = vsphere_helper.find_vm(
        bootstrap_options[:vm_folder],
        machine_spec.name
      )
      if vm
        Chef::Log.info machine_msg(
          machine_spec.name,
          vm.config.instanceUuid,
          'already created'
        )
      else
        vm = clone_vm(
          action_handler,
          bootstrap_options,
          machine_spec.name
        )
      end
      vm
    end

    def full_description(machine_spec, bootstrap_options)
      description = [ "creating machine #{machine_spec.name} on #{driver_url}" ]
      bootstrap_options.to_hash.each_pair do |key,value|
        description << "  #{key}: #{value.inspect}"
      end
      description
    end

    def machine_msg(name, id, action)
      "Machine - #{action} - #{name} (#{id} on #{driver_url})"
    end

    def ready_machine(action_handler, machine_spec, machine_options)
      merge_options! machine_options

      vm = start_machine(action_handler, machine_spec, machine_options)
      if vm.nil?
        raise "Machine #{machine_spec.name} does not have a server "\
        'associated with it, or server does not exist.'
      end

      bootstrap_options = machine_options[:bootstrap_options]

      transport_respond?(
        machine_options,
        vm,
        action_handler,
        machine_spec
      )

      machine = machine_for(machine_spec,machine_options)

      setup_extra_nics(action_handler, bootstrap_options, vm, machine)

      if has_static_ip(bootstrap_options) && !is_windows?(vm)
        setup_ubuntu_dns(machine, bootstrap_options, machine_spec)
      end

      machine
    end

    def setup_extra_nics(action_handler, bootstrap_options, vm, machine)
      networks=bootstrap_options[:network_name]
      if networks.kind_of?(String)
        networks=[networks]
      end
      return if networks.nil? || networks.count < 2

      new_nics = vsphere_helper.add_extra_nic(
        action_handler,
        vm_template_for(bootstrap_options),
        bootstrap_options,
        vm
      )
      if is_windows?(vm) && !new_nics.nil?
        new_nics.each do |nic|
          nic_label = nic.device.deviceInfo.label
          machine.execute_always(
            "Disable-Netadapter -Name '#{nic_label}' -Confirm:$false")
        end
      end
    end

    def transport_respond?(
      machine_options,
      vm,
      action_handler,
      machine_spec
    )
      bootstrap_options = machine_options[:bootstrap_options]

      # this waits for vmware tools to start and the vm to presebnt an ip
      # This may just be the ip of a newly cloned machine
      # Customization below may change this to a valid ip
      wait_until_ready(action_handler, machine_spec, machine_options, vm)

      if !machine_spec.location['ipaddress'] || !has_ip?(machine_spec.location['ipaddress'], vm)
        # find the ip we actually want
        # this will be the static ip to assign
        # or the ip reported back by the vm if using dhcp
        # it *may* be nil if just cloned
        vm_ip = ip_to_bootstrap(bootstrap_options, vm)
        transport = nil
        unless vm_ip.nil?
          transport = transport_for(machine_spec, bootstrap_options[:ssh], vm_ip)
        end

        unless !transport.nil? && transport.available? && has_ip?(vm_ip, vm)
          attempt_ip(machine_options, action_handler, vm, machine_spec)
        end
        machine_spec.location['ipaddress'] = vm.guest.ipAddress
        action_handler.report_progress(
          "IP address obtained: #{machine_spec.location['ipaddress']}")
      end

      wait_for_domain(bootstrap_options, vm, machine_spec, action_handler)

      begin
        wait_for_transport(action_handler, machine_spec, machine_options, vm)
      rescue Timeout::Error
        # Only ever reboot once, and only if it's been less than 10 minutes
        # since we stopped waiting
        if machine_spec.location['started_at'] ||
          remaining_wait_time(machine_spec, machine_options) < -(10*60)
          raise
        else
          Chef::Log.warn(machine_msg(
            machine_spec.name,
            vm.config.instanceUuid,
            'started but SSH did not come up.  Rebooting...'
          ))
          restart_server(action_handler, machine_spec, machine_options)
          wait_until_ready(action_handler, machine_spec, machine_options, vm)
          wait_for_transport(action_handler, machine_spec, machine_options, vm)
        end
      end
    end

    def attempt_ip(machine_options, action_handler, vm, machine_spec)
      vm_ip = ip_to_bootstrap(machine_options[:bootstrap_options], vm)

      wait_for_ip(vm, machine_options, machine_spec, action_handler)

      unless has_ip?(vm_ip, vm)
        action_handler.report_progress "rebooting..."
        if vm.guest.toolsRunningStatus != "guestToolsRunning"
          msg = 'tools have stopped. current power state is '
          msg << vm.runtime.powerState
          msg << ' and tools state is '
          msg << vm.guest.toolsRunningStatus
          msg << '. powering up server...'
          action_handler.report_progress(msg.join)
          vsphere_helper.start_vm(vm)
        else
          restart_server(action_handler, machine_spec, machine_options)
        end
        wait_for_ip(vm, machine_options, machine_spec, action_handler)
      end
    end

    def wait_for_domain(bootstrap_options, vm, machine_spec, action_handler)
      return unless bootstrap_options[:customization_spec]
      return unless bootstrap_options[:customization_spec][:domain]

      domain = bootstrap_options[:customization_spec][:domain]
      if is_windows?(vm) && domain != 'local'
        start = Time.now.utc
        trimmed_name = machine_spec.name.byteslice(0,15)
        expected_name="#{trimmed_name}.#{domain}"
        action_handler.report_progress(
          "waiting to domain join and be named #{expected_name}")
        until (Time.now.utc - start) > 30 ||
          (vm.guest.hostName == expected_name) do
          print '.'
          sleep 5
        end
      end
    end

    def wait_for_ip(vm, machine_options, machine_spec, action_handler)
      bootstrap_options = machine_options[:bootstrap_options]
      vm_ip = ip_to_bootstrap(bootstrap_options, vm)
      ready_timeout = machine_options[:ready_timeout] || 300
      msg = "waiting up to #{ready_timeout} seconds for customization"
      msg << " and find #{vm_ip}" unless vm_ip ==  vm.guest.ipAddress
      action_handler.report_progress msg

      start = Time.now.utc
      connectable = false
      until (Time.now.utc - start) > ready_timeout || connectable do
        action_handler.report_progress(
          "IP addresses found: #{all_ips_for(vm)}")
        vm_ip ||= ip_to_bootstrap(bootstrap_options, vm)
        if has_ip?(vm_ip, vm)
          connectable = transport_for(
            machine_spec,
            machine_options[:bootstrap_options][:ssh],
            vm_ip
          ).available?
        end
        sleep 5
      end
    end

    def all_ips_for(vm)
      vm.guest.net.map { |net| net.ipAddress}.flatten
    end

    def has_ip?(ip, vm)
      all_ips_for(vm).include?(ip)
    end

    # Connect to machine without acquiring it
    def connect_to_machine(machine_spec, machine_options)
      merge_options! machine_options
      machine_for(machine_spec, machine_options)
    end

    def destroy_machine(action_handler, machine_spec, machine_options)
      merge_options! machine_options
      vm = vm_for(machine_spec)
      if vm
        action_handler.perform_action "Delete VM [#{vm.parent.name}/#{vm.name}]" do
          begin
            vsphere_helper.stop_vm(vm, machine_options[:stop_timeout])
            vm.Destroy_Task.wait_for_completion
          rescue RbVmomi::Fault => fault
            raise fault unless fault.fault.class.wsdl_name == "ManagedObjectNotFound"
          ensure
            machine_spec.location = nil
          end
        end
      end
      strategy = convergence_strategy_for(machine_spec, machine_options)
      strategy.cleanup_convergence(action_handler, machine_spec)
    end

    def stop_machine(action_handler, machine_spec, machine_options)
      merge_options! machine_options
      vm = vm_for(machine_spec)
      if vm
        action_handler.perform_action "Shutdown guest OS and power off VM [#{vm.parent.name}/#{vm.name}]" do
          vsphere_helper.stop_vm(vm, machine_options[:stop_timeout])
        end
      end
    end

    def start_machine(action_handler, machine_spec, machine_options)
      merge_options! machine_options
      vm = vm_for(machine_spec)
      if vm
        action_handler.perform_action "Power on VM [#{vm.parent.name}/#{vm.name}]" do
          vsphere_helper.start_vm(vm, machine_options[:bootstrap_options][:ssh][:port])
        end
      end
      vm
    end

    def restart_server(action_handler, machine_spec, machine_options)
      action_handler.perform_action "restart machine #{machine_spec.name} (#{driver_url})" do
        stop_machine(action_handler, machine_spec, machine_options)
        start_machine(action_handler, machine_spec, machine_options)
        machine_spec.location['started_at'] = Time.now.utc.to_s
      end
    end

    protected

    def setup_ubuntu_dns(machine, bootstrap_options, machine_spec)
      host_lookup = machine.execute_always('host google.com')
      if host_lookup.exitstatus != 0
        if host_lookup.stdout.include?("setlocale: LC_ALL")
          machine.execute_always('locale-gen en_US && update-locale LANG=en_US')
        end
        distro = machine.execute_always("lsb_release -i | sed -e 's/Distributor ID://g'").stdout.strip
        Chef::Log.info "Found distro:#{distro}"
        if distro == 'Ubuntu'
          distro_version = (machine.execute_always("lsb_release -r | sed -e s/[^0-9.]//g")).stdout.strip.to_f
          Chef::Log.info "Found distro version:#{distro_version}"
          if distro_version>= 12.04
            Chef::Log.info "Ubuntu version 12.04 or greater. Need to patch DNS."
            interfaces_file = "/etc/network/interfaces"
            nameservers = bootstrap_options[:customization_spec][:ipsettings][:dnsServerList].join(' ')
            machine.execute_always("if ! cat #{interfaces_file} | grep -q dns-search ; then echo 'dns-search #{bootstrap_options[:customization_spec][:domain]}' >> #{interfaces_file} ; fi")
            machine.execute_always("if ! cat #{interfaces_file} | grep -q dns-nameservers ; then echo 'dns-nameservers #{nameservers}' >> #{interfaces_file} ; fi")
            machine.execute_always('/etc/init.d/networking restart')
            machine.execute_always('apt-get -qq update')
          end
        end
      end
    end

    def has_static_ip(bootstrap_options)
      if bootstrap_options.has_key?(:customization_spec)
        spec = bootstrap_options[:customization_spec]
        if spec.has_key?(:ipsettings)
          ipsettings = spec[:ipsettings]
          if ipsettings.has_key?(:ip)
            ips = [*ipsettings[:ip]]
            ips.each do |addr|
              if addr != nil
                return true
              end
            end
          end
        end
      end
      false
    end

    def remaining_wait_time(machine_spec, machine_options)
      if machine_spec.location['started_at']
        (machine_options[:start_timeout] || 600) -
          (Time.now.utc - Time.parse(machine_spec.location['started_at']))
      else
        (machine_options[:create_timeout] || 600) -
         (Time.now.utc - Time.parse(machine_spec.location['allocated_at']))
      end
    end

    def wait_until_ready(action_handler, machine_spec, machine_options, vm)
      if vm.guest.toolsRunningStatus != "guestToolsRunning"
        if action_handler.should_perform_actions
          action_handler.report_progress "waiting for #{machine_spec.name} (#{vm.config.instanceUuid} on #{driver_url}) to be ready ..."
          until remaining_wait_time(machine_spec, machine_options) < 0 ||
            (vm.guest.toolsRunningStatus == "guestToolsRunning" && !vm.guest.ipAddress.nil? && vm.guest.ipAddress.length > 0) do
            print "."
            sleep 5
          end
          action_handler.report_progress "#{machine_spec.name} is now ready"
        end
      end
    end

    def vm_for(machine_spec)
      if machine_spec.location
        vsphere_helper.find_vm_by_id(machine_spec.location['server_id'])
      else
        nil
      end
    end

    def clone_vm(action_handler, bootstrap_options, machine_name)
      vm_template = vm_template_for(bootstrap_options)

      spec_builder = CloneSpecBuilder.new(vsphere_helper, action_handler)
      clone_spec = spec_builder.build(vm_template, machine_name, bootstrap_options)
      Chef::Log.debug("Clone spec: #{clone_spec.pretty_inspect}")

      vm_folder = vsphere_helper.find_folder(bootstrap_options[:vm_folder])
      vm_template.CloneVM_Task(
        name: machine_name,
        folder: vm_folder,
        spec: clone_spec
      ).wait_for_completion

      vm = vsphere_helper.find_vm(vm_folder, machine_name)

      additional_disk_size_gb = bootstrap_options[:additional_disk_size_gb]
      if !additional_disk_size_gb.is_a?(Array)
        additional_disk_size_gb = [additional_disk_size_gb]
      end

      additional_disk_size_gb.each do |size|
        size = size.to_i
        next if size == 0
        if bootstrap_options[:datastore].to_s.empty?
          raise ':datastore must be specified when adding a disk to a cloned vm'
        end
        task = vm.ReconfigVM_Task(
          spec: RbVmomi::VIM.VirtualMachineConfigSpec(
            deviceChange: [
              vsphere_helper.virtual_disk_for(
                vm,
                bootstrap_options[:datastore],
                size
              )
            ]
          )
        )
        task.wait_for_completion
      end

      vm
    end

    def vsphere_helper
      @vsphere_helper ||= VsphereHelper.new(
        connect_options,
        config[:machine_options][:bootstrap_options][:datacenter]
      )
    end

    def vm_template_for(bootstrap_options)
      template_folder = bootstrap_options[:template_folder]
      template_name   = bootstrap_options[:template_name]
      vsphere_helper.find_vm(template_folder, template_name) ||
        raise("vSphere VM Template not found [#{template_folder}/#{template_name}]")
    end

    def machine_for(machine_spec, machine_options)
      if machine_spec.location.nil?
        raise "Server for node #{machine_spec.name} has not been created!"
      end

      transport = transport_for(
        machine_spec,
        machine_options[:bootstrap_options][:ssh]
      )
      strategy = convergence_strategy_for(machine_spec, machine_options)

      if machine_spec.location['is_windows']
        Chef::Provisioning::Machine::WindowsMachine.new(
          machine_spec, transport, strategy)
      else
        Chef::Provisioning::Machine::UnixMachine.new(
          machine_spec, transport, strategy)
      end
    end

    def is_windows?(vm)
      return false if vm.nil?
      vm.config.guestId.start_with?('win')
    end

    def convergence_strategy_for(machine_spec, machine_options)
      require 'chef/provisioning/convergence_strategy/install_msi'
      require 'chef/provisioning/convergence_strategy/install_cached'
      require 'chef/provisioning/convergence_strategy/no_converge'

      mopts = machine_options[:convergence_options].to_hash.dup
      if mopts[:chef_server]
        mopts[:chef_server] = mopts[:chef_server].to_hash.dup
        mopts[:chef_server][:options] = mopts[:chef_server][:options].to_hash.dup if mopts[:chef_server][:options]
      end

      if !machine_spec.location
        return Chef::Provisioning::ConvergenceStrategy::NoConverge.new(
          mopts, config)
      end

      if machine_spec.location['is_windows']
        Chef::Provisioning::ConvergenceStrategy::InstallMsi.new(
          mopts, config)
      else
        Chef::Provisioning::ConvergenceStrategy::InstallCached.new(
          mopts, config)
      end
    end

    def wait_for_transport(action_handler, machine_spec, machine_options, vm)
      transport = transport_for(
        machine_spec,
        machine_options[:bootstrap_options][:ssh]
      )
      if !transport.available?
        if action_handler.should_perform_actions
          action_handler.report_progress "waiting for #{machine_spec.name} (#{vm.config.instanceUuid} on #{driver_url}) to be connectable (transport up and running) ..."

          until remaining_wait_time(machine_spec, machine_options) < 0 || transport.available? do
            print "."
            sleep 5
          end

          action_handler.report_progress "#{machine_spec.name} is now connectable"
        end
      end
    end

    def transport_for(
      machine_spec,
      remoting_options,
      ip = machine_spec.location['ipaddress']
    )
      if machine_spec.location['is_windows']
        create_winrm_transport(ip, remoting_options)
      else
        create_ssh_transport(ip, remoting_options)
      end
    end

    def create_winrm_transport(host, options)
      require 'chef/provisioning/transport/winrm'
      opt = options[:user].include?("\\") ? :disable_sspi : :basic_auth_only
      winrm_options = {
        user: "#{options[:user]}",
        pass: options[:password],
        opt => true
      }

      Chef::Provisioning::Transport::WinRM.new(
        "http://#{host}:5985/wsman",
        :plaintext,
        winrm_options,
        config
      )
    end

    def create_ssh_transport(host, options)
      require 'chef/provisioning/transport/ssh'
      ssh_user = options[:user]
      Chef::Provisioning::Transport::SSH.new(
        host,
        ssh_user,
        options.to_hash,
        @config[:machine_options][:sudo] ? {:prefix => 'sudo '} : {},
        config
      )
    end

    def ip_to_bootstrap(bootstrap_options, vm)
      if has_static_ip(bootstrap_options)
        ips = [*bootstrap_options[:customization_spec][:ipsettings][:ip]]
        ips.each do |addr|
          if addr != nil
            return addr
          end
        end
      else
        vm.guest.ipAddress
      end
    end
  end
end
