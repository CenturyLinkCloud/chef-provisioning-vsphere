require_relative '../../lib/chef_metal_vsphere/vsphere_driver.rb'
require 'chef_metal/chef_machine_spec'

describe "allocate_machine" do
	metal_config = {
	  :driver_options => { 
	  	:user => 'vmapi',
	  	:password => '<password>'
	  },
	  :machine_options => { 
	  	:ssh => {
	  		:password => '<password>',
	  		:paranoid => false
	  	},
	  	:bootstrap_options => {
	  		:datacenter => 'QA1',
	  		:template_name => 'UBUNTU-12-64-TEMPLATE',
	  		:vm_folder => 'DLAB',
	  		:num_cpus => 2,
	  		:memory_mb => 4096,
	  		:resource_pool => 'CLSTR02/DLAB'
	  	}
	  },
	  :log_level => :debug
	}

	Cheffish.honor_local_mode do
		chef_server = Cheffish.default_chef_server(metal_config)
		machine_spec = ChefMetal::ChefMachineSpec.new('vtest', chef_server)
		driver = ChefMetal.driver_for_url('vsphere://172.21.10.10/api?ssl=true&insecure=true', metal_config)
		driver.allocate_machine(nil, machine_spec, metal_config[:machine_options])
		driver.ready_machine(nil, machine_spec, metal_config[:machine_options])
	end
end
