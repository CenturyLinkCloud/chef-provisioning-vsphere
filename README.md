chef-provisioning-vsphere
==================

This is a [chef-provisioning](https://github.com/opscode/chef-provisioning) provisioner for [VMware vSphere](http://www.vmware.com/products/vsphere).

Currently, chef-provisioning-vsphere supports provisioning Unix/ssh and Windows/winrm guest VMs.

Try It Out
----------

### vSphere VM Template

Create or obtain a VM template.  The VM template must:

  - be capable of installing Chef 11.8 or newer
  - run vmware-tools on system boot (provides visiblity to ip address of the running VM)
  - provide access via ssh or winrm
  - provide a user account with NOPASSWD sudo/administrator

### Example recipe

```
    chef_gem 'chef-provisioning-vsphere' do
      action :install
      compile_time true
    end

    require 'chef/provisioning/vsphere_driver'

    with_vsphere_driver host: 'vcenter-host-name',
      insecure: true,
      user:     'you_user_name',
      password: 'your_mothers_maiden_name'

    machine_options = {
      :bootstrap_options => {
        :num_cpus =>        2,
        :additional_disk_size_gb => 50,
        :memory_mb =>       4096,
        :network_name =>    ["vlan_20_172.21.20"],
        :datacenter         'datacenter_name',
        :host:               'cluster/host',
        :resource_pool:      'cluster/resource_pool_name',
        :datastore:          'datastore_name',
        :template_name:      'path to template_vm',           # may be a VM or a VM Template
        :vm_folder          'folder_to_clone_vms_into',
        :customization_spec => {
          :ipsettings => {
            :ip => '1.2.3.125',
            :subnetMask => '255.255.255.0',
            :gateway => ["1.2.3.1"],
            :dnsServerList => ["1.2.3.31","1.2.3.41"]
          },
          :domain => 'local',
          :domainAdmin => "administrator@local",
          :domainAdminPassword => "Password",
          :org_name => 'my_company',
          :product_id => 'xxxxx-xxxxx-xxxxx-xxxxx-xxxxx',
          :win_time_zone => 4
        }
        :ssh => {
          :user => 'administrator',
          :password => 'password',
          :paranoid => false,
          :port => 22
        },
        :convergence_options => {
          :install_msi_url=>"https://opscode-omnibus-packages.s3.amazonaws.com/windows/2008r2/x86_64/chef-windows-11.16.4-1.windows.msi", 
          :install_sh_url=>"/tmp/chef-install.sh -v 11.16.4"
        }
      }

      machine "my_machine_name" do
        machine_options machine_options
        run_list ['my_cookbook::default']
      end

```

