require 'kitchen/driver/vsphere_common'

module Kitchen
  module Driver
    class VsphereWindows < Kitchen::Driver::WinRMBase

      default_config :machine_options,
        :start_timeout => 600,
        :create_timeout => 600,
        :ready_timeout => 90,
        :bootstrap_options => {
          :use_linked_clone => true,
          :ssh => {
            :user => 'administrator',
          },
          :convergence_options => {},
          :customization_spec => {
            :domain => 'local',
            :org_name => 'Tier3',
            :product_id => 'W3GGN-FT8W3-Y4M27-J84CP-Q3VJ9',
            :win_time_zone => 4
          }
        }

      include Kitchen::Driver::VsphereCommon

    end
  end
end
