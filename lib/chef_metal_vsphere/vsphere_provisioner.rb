require 'chef_metal/provisioner'
require 'chef_metal/machine/windows_machine'
require 'chef_metal/machine/unix_machine'
require 'chef_metal/convergence_strategy/install_msi'
require 'chef_metal/convergence_strategy/install_cached'
require 'chef_metal/transport/ssh'
require 'chef_metal_vsphere/version'
require 'rbvmomi'
require 'chef_metal_vsphere/vsphere_helpers'

module ChefMetalVsphere
  # Provisions machines in vSphere.
  class VsphereProvisioner < ChefMetal::Provisioner

    include Chef::Mixin::ShellOut
    include ChefMetalVsphere::Helpers

    def self.inflate(node)
      url = node['normal']['provisioner_output']['provisioner_url']
      scheme, provider, id = url.split(':', 3)
      VsphereProvisioner.new({ :provider => provider }, id)
    end

    # Create a new Vsphere provisioner.
    #
    # ## Parameters
    # connect_options - hash of options to be passed to RbVmomi::VIM.connect
    #   :vsphere_host       - required - hostname of the vSphere API server
    #   :vsphere_port       - optional - port on the vSphere API server (default: 443)
    #   :vshere_path        - optional - path on the vSphere API server (default: /sdk)
    #   :vsphere_ssl        - optional - true to use ssl in connection to vSphere API server (default: true)
    #   :vsphere_insecure   - optional - true to ignore ssl certificate validation errors in connection to vSphere API server (default: false)
    #   :vsphere_user       - required - user name to use in connection to vSphere API server
    #   :vsphere_password   - required - password to use in connection to vSphere API server
    #   :proxy_host         - optional - http proxy host to use in connection to vSphere API server (default: none)
    #   :proxy_port         - optional - http proxy port to use in connection to vSphere API server (default: none)
    def initialize(connect_options)
      connect_options = stringify_keys(connect_options)
      default_connect_options = {
        'vsphere_port'     => 443,
        'vsphere_ssl'      => true,
        'vsphere_insecure' => false,
        'vsphere_path'     => '/sdk'
      }

      @connect_options = default_connect_options.merge(connect_options)

      required_options = %w( vsphere_host vsphere_user vsphere_password )
      missing_options = []
      required_options.each do |opt|
        missing_options << opt unless @connect_options.has_key?(opt)
      end
      unless missing_options.empty?
        raise "missing required options: #{missing_options.join(', ')}"
      end

      # test vim connection
      vim || raise("cannot connect to [#{provisioner_url}]")

      @connect_options
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
    def acquire_machine(action_handler, node)
      # Set up the provisioner output
      provisioner_options = stringify_keys(node['normal']['provisioner_options'])

      vm_name = node['name']
      old_provisioner_output = node['normal']['provisioner_output']
      node['normal']['provisioner_output'] = provisioner_output = {
        'provisioner_url' => provisioner_url,
        'vm_name' => vm_name,
        'bootstrap_options' => provisioner_options['bootstrap_options']
      }

      bootstrap_options = node['normal']['provisioner_output']['bootstrap_options']
      vm_folder = bootstrap_options['vm_folder']

      if bootstrap_options['ssh']
        wait_on_port = bootstrap_options['ssh']['port']
        raise "Must specify bootstrap_options[:ssh][:port]" if wait_on_port.nil?
      else
        raise 'bootstrapping is currently supported for ssh only'
        # wait_on_port = bootstrap_options['winrm']['port']
      end

      # TODO compare new options to existing and fail if we cannot change it
      # over (perhaps introduce a boolean that will force a delete and recreate
      # in such a case)

      vm = vm_instance(action_handler, node)

      unless vm_started?(vm, wait_on_port)
        action_handler.perform_action "Start VM and wait for port #{wait_on_port}" do
          start_vm(vm, wait_on_port)
        end
      end

      machine = machine_for(node)

      machine
    end

    # Connect to machine without acquiring it
    def connect_to_machine(node)
      machine_for(node)
    end

    def delete_machine(action_handler, node)
      if node['normal'] && node['normal']['provisioner_output']
        provisioner_output = node['normal']['provisioner_output']
      else
        provisioner_output = {}
      end
      vm_name = provisioner_output['vm_name'] || node['name']
      vm_folder = provisioner_output['bootstrap_options']['vm_folder']
      vm = vm_for(node)

      unless vm.nil?
        action_handler.perform_action "Delete VM [#{vm_folder}/#{vm_name}]" do
          vm.PowerOffVM_Task.wait_for_completion unless vm.runtime.powerState == 'poweredOff'
          vm.Destroy_Task.wait_for_completion
        end
      end
    end

    def stop_machine(action_handler, node)
      if node['normal'] && node['normal']['provisioner_output']
        provisioner_output = node['normal']['provisioner_output']
      else
        provisioner_output = {}
      end
      vm_name = provisioner_output['vm_name'] || node['name']
      vm_folder = provisioner_output['bootstrap_options']['vm_folder']
      vm = vm_for(node)

      unless vm_stopped?(vm)
        action_handler.perform_action "Shutdown guest OS and power off VM [#{vm_folder}/#{vm_name}]" do
          stop_vm(vm)
        end
      end
    end

    protected

    def provisioner_url
      "vsphere://#{connect_options['vsphere_host']}:#{connect_options['vsphere_port']}#{connect_options['vsphere_path']}?ssl=#{connect_options['vsphere_ssl']}&insecure=#{connect_options['vsphere_insecure']}"
    end

    def vm_instance(action_handler, node)
      bootstrap_options = node['normal']['provisioner_output']['bootstrap_options']

      datacenter = bootstrap_options['datacenter']
      vm_name = node['normal']['provisioner_output']['vm_name']
      vm_folder = bootstrap_options['vm_folder']

      vm = find_vm(datacenter, vm_folder, vm_name)
      return vm unless vm.nil?

      action_handler.perform_action "Clone a new VM instance from [#{bootstrap_options['template_folder']}/#{bootstrap_options['template_name']}]" do
        vm = clone_vm(vm_name, bootstrap_options)
      end

      vm
    end

    def clone_vm(vm_name, bootstrap_options)
      datacenter      = bootstrap_options['datacenter']
      template_folder = bootstrap_options['template_folder']
      template_name   = bootstrap_options['template_name']

      vm_template = find_vm(datacenter, template_folder, template_name) or raise("vSphere VM Template not found [#{template_folder}/#{template_name}]")

      vm = do_vm_clone(datacenter, vm_template, vm_name, bootstrap_options)
    end

    def machine_for(node)
      vm = vm_for(node) or raise "VM for node #{node['name']} has not been created!"

      if is_windows?(vm)
        ChefMetal::Machine::WindowsMachine.new(node, transport_for(node), convergence_strategy_for(node))
      else
        ChefMetal::Machine::UnixMachine.new(node, transport_for(node), convergence_strategy_for(node))
      end
    end


    def vm_for(node)
      bootstrap_options = node['normal']['provisioner_output']['bootstrap_options']
      datacenter = bootstrap_options['datacenter']
      vm_folder = bootstrap_options['vm_folder']
      vm_name = node['normal']['provisioner_output']['vm_name']
      vm = find_vm(datacenter, vm_folder, vm_name)
      vm
    end

    def is_windows?(vm)
      return false if vm.nil?
      vm.guest.guestFamily == 'windowsGuest'
    end

    def convergence_strategy_for(node)
      if is_windows?(vm_for(node))
        @windows_convergence_strategy ||= begin
          options = {}
          provisioner_options = node['normal']['provisioner_options'] || {}
          options[:chef_client_timeout] = provisioner_options['chef_client_timeout'] if provisioner_options.has_key?('chef_client_timeout')
          ChefMetal::ConvergenceStrategy::InstallMsi.new(options)
        end
      else
        @unix_convergence_strategy ||= begin
          options = {}
          provisioner_options = node['normal']['provisioner_options'] || {}
          options[:chef_client_timeout] = provisioner_options['chef_client_timeout'] if provisioner_options.has_key?('chef_client_timeout')
          ChefMetal::ConvergenceStrategy::InstallCached.new(options)
        end
      end
    end

    def transport_for(node)
      if is_windows?(vm_for(node))
        create_winrm_transport(node)
      else
        create_ssh_transport(node)
      end
    end

    def create_winrm_transport(node)
      raise 'Windows guest VMs are not yet supported'
    end

    def create_ssh_transport(node)
      bootstrap_options = node['normal']['provisioner_output']['bootstrap_options']
      vm = vm_for(node) or raise "VM for node #{node['name']} has not been created!"

      hostname = vm.guest.ipAddress
      ssh_user = bootstrap_options['ssh']['user']
      ssh_options = symbolize_keys(bootstrap_options['ssh'])
      transport_options = {
        :prefix => 'sudo '
      }
      ChefMetal::Transport::SSH.new(hostname, ssh_user, ssh_options, transport_options)
    end

    def stringify_keys(h)
      Hash === h ?
        Hash[
          h.map do |k, v|
            [k.respond_to?(:to_s) ? k.to_s : k, stringify_keys(v)]
          end
        ] : h
    end

    def symbolize_keys(h)
      Hash === h ?
        Hash[
          h.map do |k, v|
            [k.respond_to?(:to_sym) ? k.to_sym : k, symbolize_keys(v)]
          end
        ] : h
    end
  end
end
