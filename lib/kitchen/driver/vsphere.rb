require 'json'
require 'kitchen'
require 'chef/provisioning/vsphere_driver'
require 'chef/provisioning/machine_spec'

module Kitchen
  module Driver
    class Vsphere < Kitchen::Driver::Base

      @@chef_zero_server = false

      default_config :machine_options,
        :start_timeout => 600,
        :create_timeout => 600,
        :stop_timeout => 600,
        :ready_timeout => 90,
        :bootstrap_options => {
          :use_linked_clone => true,
          :ssh => {
            :user => 'root',
            :paranoid => false,
            :port => 22
          },
          :convergence_options => {},
          :customization_spec => {
            :domain => 'local'
          }
        }

      default_config(:vsphere_name) do |driver|
        "#{driver.instance.name}-#{SecureRandom.hex(4)}"
      end

      def create(state)
        state[:vsphere_name] = config[:vsphere_name]
        state[:username] = config[:machine_options][:bootstrap_options][:ssh][:user]
        state[:password] = config[:machine_options][:bootstrap_options][:ssh][:password]
        config[:server_name] = state[:vsphere_name]

        machine = with_provisioning_driver(state) do | action_handler, driver, machine_spec|
          driver.allocate_machine(action_handler, machine_spec, config[:machine_options])
          driver.ready_machine(action_handler, machine_spec, config[:machine_options])
          state[:server_id] = machine_spec.location['server_id']
          state[:hostname] = machine_spec.location['ipaddress']
          machine_spec.save(action_handler)
        end
      end

      def destroy(state)
        return if state[:server_id].nil?

        with_provisioning_driver(state) do | action_handler, driver, machine_spec|
          machine_spec.location = { 'driver_url' => driver.driver_url,
                        'server_id' => state[:server_id]}
          driver.destroy_machine(action_handler, machine_spec, config[:machine_options])
        end

        state.delete(:server_id)
        state.delete(:hostname)
        state.delete(:vsphere_name)
      end

      def with_provisioning_driver(state, &block)
        config[:machine_options][:convergence_options] = {:chef_server => chef_server}
        machine_spec = Chef::Provisioning.chef_managed_entry_store(chef_server).get(:machine, state[:vsphere_name])
        if machine_spec.nil?
          machine_spec = Chef::Provisioning.chef_managed_entry_store(chef_server)
            .new_entry(:machine, state[:vsphere_name])
        end
        url = URI::VsphereUrl.from_config(@config[:driver_options]).to_s
        driver = Chef::Provisioning.driver_for_url(url, config)
        action_handler = Chef::Provisioning::ActionHandler.new
        block.call(action_handler, driver, machine_spec)
      end

      def chef_server
        if !@@chef_zero_server
          vsphere_mutex.synchronize do
            if !@@chef_zero_server
              Chef::Config.local_mode = true
              Chef::Config.chef_repo_path = Chef::Config.find_chef_repo_path(Dir.pwd)
              require 'chef/local_mode'
              Chef::LocalMode.setup_server_connectivity
              @@chef_zero_server = true
            end
          end
        end

        Cheffish.default_chef_server
      end

      def vsphere_mutex
        @@vsphere_mutex ||= begin
          Kitchen.mutex.synchronize do
            instance.class.mutexes ||= Hash.new
            instance.class.mutexes[self.class] = Mutex.new
          end

          instance.class.mutexes[self.class]
        end
      end
    end
  end
end
