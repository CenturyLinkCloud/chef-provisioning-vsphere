require 'chef/provisioning/vsphere_driver'
require 'chef/provisioning/machine_spec'

  # A file named config.rb in the same directory as this spec file 
  # must exist containing the driver options to use for the test.
  # Here is an example:
  # {
  #   :driver_options => { 
  #     :host => '213.45.67.88',
  #     :user => 'vmapi',
  #     :password => 'SuperSecureP@ssw0rd',
  #     :insecure => true
  #   },
  #   :machine_options => { 
  #     :start_timeout => 600, 
 #            :create_timeout => 600,       
 #            :bootstrap_options => {
  #       :datacenter => 'QA1',
  #       :template_name => 'UBUNTU-12-64-TEMPLATE',
  #       :vm_folder => 'DLAB',
  #       :num_cpus => 2,
  #       :network_name => 'vlan152_172.21.152',
  #       :memory_mb => 4096,
  #       :resource_pool => 'CLSTR02/DLAB',
  #       :ssh => {
  #         :user => 'root',
  #         :password => 'SuperSecureP@ssw0rd',
  #         :paranoid => false,
  #         :port => 22
  #       },
  #       :convergence_options => {}
  #     }
  #   }
  # }

describe "vsphere_driver" do
  include ChefProvisioningVsphere::Helpers

  before :all do
    @vm_name = "cmvd-test-#{SecureRandom.hex}"
    @metal_config = eval File.read(File.expand_path('../config.rb', __FILE__))
    Cheffish.honor_local_mode do
      chef_server = Cheffish.default_chef_server
      @machine_spec = Chef::Provisioning.chef_managed_entry_store(chef_server).new_entry(:machine, @vm_name)
      url = URI::VsphereUrl.from_config(@metal_config[:driver_options]).to_s
      @driver = Chef::Provisioning.driver_for_url(url, @metal_config)
      action_handler = Chef::Provisioning::ActionHandler.new
      @driver.allocate_machine(action_handler, @machine_spec, @metal_config[:machine_options])
      @metal_config[:machine_options][:convergence_options] = {:chef_server => chef_server}
      machine = @driver.ready_machine(action_handler, @machine_spec, @metal_config[:machine_options])
      @server_id = @machine_spec.location['server_id']
      @connection = vim(@metal_config[:driver_options])
      @vm = find_vm_by_id(@server_id, @connection)
    end
  end


  context 'when allocating a machine' do

    it "adds machine to the correct folder" do
      expect(@vm.parent.name).to eq(@metal_config[:machine_options][:bootstrap_options][:vm_folder])
    end
    it "has a matching id with the machine_spec" do
      expect(@vm.config.instanceUuid).to eq(@machine_spec.location['server_id'])
    end
    it "has the correct name" do
          now = Time.now.utc
          trimmed_name = @vm.config.guestId.start_with?('win') ? @vm_name.byteslice(0,15) : @vm_name
          expected_name="#{trimmed_name}.#{@metal_config[:machine_options][:bootstrap_options][:customization_spec][:domain]}"
          until (Time.now.utc - now) > 30 || (@vm.guest.hostName == expected_name) do
            print "."
            sleep 5
          end
      expect(@vm.guest.hostName).to eq(expected_name)
    end
    it "has the correct number of CPUs" do
      expect(@vm.config.hardware.numCPU).to eq(@metal_config[:machine_options][:bootstrap_options][:num_cpus])
    end
    it "has the correct amount of memory" do
      expect(@vm.config.hardware.memoryMB).to eq(@metal_config[:machine_options][:bootstrap_options][:memory_mb])
    end
    it "is on the correct networks" do
      expect(@vm.network.map {|n| n.name}).to include(@metal_config[:machine_options][:bootstrap_options][:network_name][0])
      expect(@vm.network.map {|n| n.name}).to include(@metal_config[:machine_options][:bootstrap_options][:network_name][1])
    end
    it "is on the correct datastore" do
      expect(@vm.datastore[0].name).to eq(@metal_config[:machine_options][:bootstrap_options][:datastore])
    end
    it "is in the correct resource pool" do
      if @metal_config[:machine_options][:bootstrap_options].has_key?(:resource_pool)
        expect(@vm.resourcePool.name).to eq(@metal_config[:machine_options][:bootstrap_options][:resource_pool].split('/')[1])
      end
    end
    it "is in the correct host" do
      if @metal_config[:machine_options][:bootstrap_options].has_key?(:host)
        expect(@vm.runtime.host.name).to eq(@metal_config[:machine_options][:bootstrap_options][:host].split('/')[1])
      end
    end
    it "is in the correct cluster" do
      if @metal_config[:machine_options][:bootstrap_options].has_key?(:resource_pool)
        expect(@vm.resourcePool.owner.name).to eq(@metal_config[:machine_options][:bootstrap_options][:resource_pool].split('/')[0])
      end
    end
    it "is in the correct datacenter" do
      expect(@connection.serviceInstance.find_datacenter(@metal_config[:machine_options][:bootstrap_options][:datacenter]).find_vm("#{@vm.parent.name}/#{@vm_name}")).not_to eq(nil)
    end
    it "has an added disk of the correct size" do
      disk_count = @vm.disks.count
      expect(@vm.disks[disk_count-1].capacityInKB).to eq(@metal_config[:machine_options][:bootstrap_options][:additional_disk_size_gb] * 1024 * 1024)
    end
    it "has hot add cpu enabled" do
      expect(@vm.config.cpuHotAddEnabled).to eq(true)
    end
    it "has hot remove cpu enabled" do
      expect(@vm.config.cpuHotRemoveEnabled).to eq(true)
    end
    it "has hot add memory enabled" do
      expect(@vm.config.memoryHotAddEnabled).to eq(true)
    end   
    it "has the correct IP address" do
        if @vm.guest.toolsRunningStatus != "guestToolsRunning"
          now = Time.now.utc
          until (Time.now.utc - now) > 30 || (@vm.guest.toolsRunningStatus == "guestToolsRunning" && @vm.guest.net.count == 2 && @vm.guest.net[1].ipAddress[1] == @metal_config[:machine_options][:bootstrap_options][:customization_spec][:ipsettings][:ip]) do
            print "."
            sleep 5
          end
        end
      expect(@vm.guest.net.map { |net| net.ipAddress}.flatten).to include(@metal_config[:machine_options][:bootstrap_options][:customization_spec][:ipsettings][:ip])
    end
  end

  context "destroy_machine" do

    it "removes the machine" do
      Cheffish.honor_local_mode do
        chef_server = Cheffish.default_chef_server
        url = URI::VsphereUrl.from_config(@metal_config[:driver_options]).to_s
        driver = Chef::Provisioning.driver_for_url(url, @metal_config)
        action_handler = Chef::Provisioning::ActionHandler.new
        machine_spec = Chef::Provisioning.chef_managed_entry_store(chef_server).new_entry(:machine, @vm_name)
        machine_spec.location = { 
          'driver_url' => driver.driver_url,
          'server_id' => @server_id
        }
        driver.destroy_machine(action_handler, machine_spec, @metal_config[:machine_options])
      end
      vm = find_vm_by_id(@server_id, @connection)
      expect(vm).to eq(nil)
    end
  end
end
