require 'kitchen/driver/vsphere_common'

module Kitchen
  module Driver
    class Vsphere < Kitchen::Driver::SSHBase

      default_config :machine_options,
        :start_timeout => 600,
        :create_timeout => 600,
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

      include Kitchen::Driver::VsphereCommon

    end
  end
end
