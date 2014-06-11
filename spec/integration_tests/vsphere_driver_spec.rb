require 'chef_metal_vsphere/vsphere_driver.rb'
require 'chef_metal/chef_machine_spec'

	# A file named config.rb in the same directory as this spec file 
	# must exist containing the driver options to use for the test.
	# Here is an example:
	# {
	#   :driver_options => { 
	#   	:host => '213.45.67.88',
	#   	:user => 'vmapi',
	#   	:password => 'SuperSecureP@ssw0rd',
	#   	:insecure => true
	#   },
	#   :machine_options => { 
	# 		:start_timeout => 600, 
 #            :create_timeout => 600, 	  	
 #            :bootstrap_options => {
	#   		:datacenter => 'QA1',
	#   		:template_name => 'UBUNTU-12-64-TEMPLATE',
	#   		:vm_folder => 'DLAB',
	#   		:num_cpus => 2,
	#   		:network_name => 'vlan152_172.21.152',
	#   		:memory_mb => 4096,
	#   		:resource_pool => 'CLSTR02/DLAB',
	# 	  	:ssh => {
	# 	  		:user => 'root',
	# 	  		:password => 'SuperSecureP@ssw0rd',
	# 	  		:paranoid => false,
	# 	  		:port => 22
	# 	  	},
	# 	  	:convergence_options => {}
	#   	}
	#   }
	# }

describe "allocate_machine" do
    include ChefMetalVsphere::Helpers
	before :all do
		@metal_config = eval File.read(File.expand_path('../config.rb', __FILE__))
		Cheffish.honor_local_mode do
			chef_server = Cheffish.default_chef_server(@metal_config)
			machine_spec = ChefMetal::ChefMachineSpec.new({'name' => 'vtest'}, chef_server)
			driver = ChefMetal.driver_for_url("vsphere://#{@metal_config[:driver_options][:host]}", @metal_config)
			action_handler = ChefMetal::ActionHandler.new
			driver.allocate_machine(action_handler, machine_spec, @metal_config[:machine_options])
			@metal_config[:machine_options][:convergence_options] = {}
			driver.ready_machine(action_handler, machine_spec, @metal_config[:machine_options])
			connection = vim(@metal_config[:driver_options])
			@vm = find_vm_by_id(machine_spec.location['server_id'], connection)
		end
	end

	it "adds machine to the correct folder" do
		expect(@vm.parent.name).to eq(@metal_config[:machine_options][:bootstrap_options][:vm_folder])
	end
end
