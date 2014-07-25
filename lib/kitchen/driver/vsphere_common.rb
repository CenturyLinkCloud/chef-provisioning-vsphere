require 'benchmark'
require 'kitchen'
require 'chef_metal_vsphere/vsphere_driver'
require 'chef_metal/chef_machine_spec'

module Kitchen
  module Driver
  	module VsphereCommon
      def create(state)
        config[:server_name] ||= "kitchen-#{instance.name}-#{SecureRandom.hex}"
        state[:username] = config[:machine_options][:bootstrap_options][:ssh][:user]
        state[:password] = config[:machine_options][:bootstrap_options][:ssh][:password]
        
        machine = with_metal_driver(config[:server_name]) do | action_handler, driver, machine_spec|
      	  driver.allocate_machine(action_handler, machine_spec, config[:machine_options])
      	  driver.ready_machine(action_handler, machine_spec, config[:machine_options])
          state[:server_id] = machine_spec.location['server_id']
          state[:hostname] = machine_spec.location['ipaddress']
          state[:vsphere_name] = config[:server_name]
        end
      end

      def destroy(state)
        return if state[:server_id].nil?

        with_metal_driver(state[:vsphere_name]) do | action_handler, driver, machine_spec|
          machine_spec.location = { 'driver_url' => driver.driver_url,
                        'server_id' => state[:server_id]}
          driver.destroy_machine(action_handler, machine_spec, config[:machine_options])
        end

        state.delete(:server_id)
        state.delete(:hostname)
        state.delete(:vsphere_name)
      end

      def with_metal_driver(name, &block)
        Cheffish.honor_local_mode do
          chef_server = Cheffish.default_chef_server(Cheffish.profiled_config)
          config[:machine_options][:convergence_options] = {:chef_server => chef_server}
          machine_spec = ChefMetal::ChefMachineSpec.new({'name' => name}, chef_server)
          driver = ChefMetal.driver_for_url("vsphere://#{config[:driver_options][:host]}", config)
          action_handler = ChefMetal::ActionHandler.new
          block.call(action_handler, driver, machine_spec)
        end
      end
  	end
  end
end