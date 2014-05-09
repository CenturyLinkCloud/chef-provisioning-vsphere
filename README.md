chef-metal-vsphere
==================

This is a [chef-metal](https://github.com/opscode/chef-metal) provisioner for [VMware vSphere](http://www.vmware.com/products/vsphere).

Currently, chef-metal-vsphere supports provisioning Unix/ssh guest VMs.

Try It Out
----------

### vSphere VM Template

Create or obtain a unix/linux VM template.  The VM template must:

  - be capable of installing Chef 11.8 or newer
  - run vmware-tools on system boot (provides visiblity to ip address of the running VM)
  - provide access via ssh
  - provide a user account with NOPASSWD sudo

### Example recipe

    require 'chef_metal_vsphere'

    with_vsphere_provisioner vsphere_host: 'vcenter-host-name',
      vsphere_insecure: true,
      vsphere_user:     'you_user_name',
      vsphere_password: 'your_mothers_maiden_name'     # consider using a chef-vault

    with_provisioner_options('bootstrap_options' => {
      datacenter:      'datacenter_name',
      cluster:         'cluster_name',
      resource_pool:   'resource_pool_name',            # often the same as the cluster_name
      datastore:       'datastore_name',
      template_name:   'name_of_template_vm',           # may be a VM or a VM Template
      template_folder: 'folder_containing_template_vm',
      vm_folder:       'folder_to_clone_vms_into',

      ssh: {                                             # net-ssh start() options
        user:                  'username_on_vm',         # must have nopasswd sudo
        password:              'name_of_your_first_pet', # consider using a chef-vault
        port:                  22,
        auth_methods:          ['password'],
        user_known_hosts_file: '/dev/null',              # don't do this in production
        paranoid:              false,                    # don't do this in production, either
        keys:                  [ ],                      # consider using a chef-vault
        keys_only:             false
        }
      })

    1.upto 2 do |n|
      machine "metal_#{n}" do
        action [:create]
      end

      machine_file "/tmp/metal_#{n}.txt" do
        machine "metal_#{n}"
        content "Hello machine #{n}!"
      end

      machine "metal_#{n}" do
        action [:stop]
      end

      machine "metal_#{n}" do
        # note: no need to :stop before :delete
        action [:delete]
      end

    end

This will clone your VM template to create two VMware Virtual Machines, "metal_1" and "metal_2", in the vSphere Folder specified by vm_folder, bootstrapped to an empty runlist.  It will then stop (guest shutdown) and delete the vms.

Bugs and Contact
----------------

Please submit bugs at [https://github.com/RallySoftware-cookbooks/chef-metal-vsphere], contact Brian Dupras on Twitter at @briandupras, email at rallysoftware-cookbooks@rallydev.com.
