require 'chef/provisioning/vsphere_driver'

describe ChefProvisioningVsphere::VsphereDriver do
  subject do
    Chef::Provisioning.driver_for_url(
      'vsphere://3.3.3.3:999/crazyapi?use_ssl=false&insecure=true',
      metal_config
    )
  end

  context "when config does not include the properties included in the url" do
    let(:metal_config) do
      {
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
    end

    it "populates the connect options with correct host from the driver url" do
      expect(subject.connect_options[:host]).to eq('3.3.3.3')
    end
    it "populates the connect options with correct port from the driver url" do
      expect(subject.connect_options[:port]).to eq(999)
    end
    it "populates the connect options with correct path from the driver url" do
      expect(subject.connect_options[:path]).to eq('/crazyapi')
    end
    it "populates the connect options with correct use_ssl setting from the driver url" do
      expect(subject.connect_options[:use_ssl]).to eq(false)
    end
    it "populates the connect options with correct insecure setting from the driver url" do
      expect(subject.connect_options[:insecure]).to eq(true)
    end
  end

  context "when config keys are stringified" do
    let(:metal_config) do
      {
        'driver_options' => {
          'user' => 'vmapi',
          'password' => '<driver_password>'
        },
        'bootstrap_options' => {
          'machine_options' => {
            'datacenter' => 'QA1',
            'ssh' => {
              'password' => '<machine_password>'
            }
          }
        }
      }
    end

    it "will symbolize user" do
      expect(subject.connect_options[:user]).to eq('vmapi')
    end
    it "will symbolize password" do
      expect(subject.connect_options[:password]).to eq('<driver_password>')
    end
    it "will symbolize ssh password" do
      expect(subject.config[:bootstrap_options][:machine_options][:ssh][:password]).to eq('<machine_password>')
    end
    it "will symbolize ssh bootstrap options" do
      expect(subject.config[:bootstrap_options][:machine_options][:datacenter]).to eq('QA1')
    end
  end

  describe 'canonicalize_url' do
    context "when no url is in the config" do
      let(:metal_config) do
        {
          :driver_options => { 
            :user => 'vmapi',
            :password => '<password>',
            :host => '4.4.4.4',
            :port => 888,
            :path => '/yoda',
            :use_ssl => false,
            :insecure => true
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
      end

      subject do
        ChefProvisioningVsphere::VsphereDriver.canonicalize_url(
          nil, 
          metal_config
        )
      end

      it "creates the correct driver url from config settings" do
        expect(subject[0]).to eq('vsphere://4.4.4.4:888/yoda?use_ssl=false&insecure=true')
      end
    end

    context "when no url is in the config and config is missing defaulted values" do
      let(:metal_config) do
        {
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
      end

      subject do
        ChefProvisioningVsphere::VsphereDriver.canonicalize_url(
          nil,
          metal_config
        )
      end

      it "creates the correct driver url from default settings" do
        expect(subject[0]).to eq('vsphere://4.4.4.4/sdk?use_ssl=true&insecure=false')
      end
    end
  end
end
