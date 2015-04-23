require 'chef/provisioning/vsphere_driver'

describe "canonicalize_url" do

	context "when config does not include the properties included in the url" do
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

		let(:results) {
			ChefProvisioningVsphere::VsphereDriver.canonicalize_url('vsphere://3.3.3.3:999/crazyapi?use_ssl=false&insecure=true', metal_config)
		}

		it "populates the config with correct host from the driver url" do
			expect(results[1][:driver_options][:connect_options][:host]).to eq('3.3.3.3')
		end
		it "populates the config with correct port from the driver url" do
			expect(results[1][:driver_options][:connect_options][:port]).to eq(999)
		end
		it "populates the config with correct path from the driver url" do
			expect(results[1][:driver_options][:connect_options][:path]).to eq('/crazyapi')
		end
		it "populates the config with correct use_ssl setting from the driver url" do
			expect(results[1][:driver_options][:connect_options][:use_ssl]).to eq(false)
		end
		it "populates the config with correct insecure setting from the driver url" do
			expect(results[1][:driver_options][:connect_options][:insecure]).to eq(true)
		end
	end

	context "when config keys are stringified" do
		metal_config = {
		  'driver_options' => { 
		  	'user' => 'vmapi',
		  	'password' => '<password>'
		  },
		  'machine_options' => { 
		  	'ssh' => {
		  		'password' => '<password>'
		  	},
		  	'bootstrap_options' => {
		  		'datacenter' => 'QA1'
		  	}
		  }
		 }

		let(:results) {
			ChefProvisioningVsphere::VsphereDriver.canonicalize_url('vsphere://3.3.3.3:999/crazyapi?use_ssl=false&insecure=true', metal_config)
		}

		it "will symbolize user" do
			expect(results[1][:driver_options][:connect_options][:user]).to eq('vmapi')
		end
		it "will symbolize password" do
			expect(results[1][:driver_options][:connect_options][:password]).to eq('<password>')
		end
		it "will symbolize ssh password" do
			expect(results[1][:machine_options][:ssh][:password]).to eq('<password>')
		end
		it "will symbolize ssh bootstrap options" do
			expect(results[1][:machine_options][:bootstrap_options][:datacenter]).to eq('QA1')
		end
	end

	context "when no url is in the config" do
		metal_config = {
		  :driver_options => { 
		  	:user => 'vmapi',
		  	:password => '<password>',
		  	:host => '4.4.4.4',
		  	:port => 888,
		  	:path => '/yoda',
		  	:use_ssl => 'false',
		  	:insecure => 'true'
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

		let(:results) {
			ChefProvisioningVsphere::VsphereDriver.canonicalize_url(nil, metal_config)
		}

		it "creates the correct driver url from config settings" do
			expect(results[0]).to eq('vsphere://4.4.4.4:888/yoda?use_ssl=false&insecure=true')
		end
	end

	context "when no url is in the config and config is missing defaulted values" do
		metal_config = {
		  :driver_options => { 
		  	:user => 'vmapi',
		  	:password => '<password>',
		  	:host => '4.4.4.4'
		  },
		  :machine_options => { 
		  	:bootstrap_options => {
		  		:datacenter => 'QA1',
		  		:template_name => 'UBUNTU-12-64-TEMPLATE',
		  		:vm_folder => 'DLAB',
		  		:num_cpus => 2,
		  		:memory_mb => 4096,
		  		:resource_pool => 'CLSTR02/DLAB',
			  	:ssh => {
			  		:password => '<password>',
			  		:paranoid => false
			  	}
		  	}
		  },
		  :log_level => :debug
		}

		let(:results) {
			ChefProvisioningVsphere::VsphereDriver.canonicalize_url(nil, metal_config)
		}

		it "creates the correct driver url from default settings" do
			expect(results[0]).to eq('vsphere://4.4.4.4/sdk?use_ssl=true&insecure=false')
		end
		it "populates the config with correct port from default settings" do
			expect(results[1][:driver_options][:connect_options][:port]).to eq(443)
		end
		it "populates the config with correct path from default settings" do
			expect(results[1][:driver_options][:connect_options][:path]).to eq('/sdk')
		end
		it "populates the config with correct use_ssl setting from default settings" do
			expect(results[1][:driver_options][:connect_options][:use_ssl]).to eq(true)
		end
		it "populates the config with correct insecure setting from default settings" do
			expect(results[1][:driver_options][:connect_options][:insecure]).to eq(false)
		end
		it "populates the config with correct ssh port from default settings" do
			expect(results[1][:machine_options][:bootstrap_options][:ssh][:port]).to eq(22)
		end
	end

	context "when missing host" do
		metal_config = {
		  :driver_options => { 
		  	:user => 'vmapi',
		  	:password => '<password>',
		  }
		}

		it "should raise an error" do
			expect{ChefProvisioningVsphere::VsphereDriver.canonicalize_url(nil,metal_config)}.to raise_error(RuntimeError)
		end
	end

	context "when missing user" do
		metal_config = {
		  :driver_options => { 
		  	:host => 'host',
		  	:password => '<password>',
		  }
		}

		it "should raise an error" do
			expect{ChefProvisioningVsphere::VsphereDriver.canonicalize_url(nil,metal_config)}.to raise_error(RuntimeError)
		end
	end

	context "when missing password" do
		metal_config = {
		  :driver_options => { 
		  	:host => 'host',
		  	:user => 'user',
		  }
		}

		it "should raise an error" do
			expect{ChefProvisioningVsphere::VsphereDriver.canonicalize_url(nil,metal_config)}.to raise_error(RuntimeError)
		end
	end	
end
