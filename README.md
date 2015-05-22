chef-provisioning-vsphere
==================

This is a [chef-provisioning](https://github.com/opscode/chef-provisioning) provisioner for [VMware vSphere](http://www.vmware.com/products/vsphere).

chef-provisioning-vsphere supports provisioning Unix/ssh and Windows/winrm guest VMs.

## Prerequisites

### Vsphere infrastructure

A vcenter and valid login credentials.

### VM Teplate

A VM template capable of installing Chef 11.8 or newer. This can be either windows or linux flavored.

### A provisioning node (can be local)

An environment equipped with the chef client and the chef-Provision-vsphere gem.

## A basic provisioning recipe

This is a minimal machine devinition that will use a dhcp assigned ip (it assumes the presense of a dhcp server). For test purposes this uses a linked clone for a faster provisioning time. This recipe should be used with a linux template. Windows provisioned servers need to point to a chef server for the cookbooks since winrm does not support port forwarding and there fore cannot reach back on the chef-zero port to get the local cookbooks. See examples below.

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

with_machine_options :bootstrap_options => {
  use_linked_clone: true,
  num_cpus: 2,
  memory_mb: 4096,
  network_name: ["vlan_20_172.21.20"],
  datacenter: 'datacenter_name',
  resource_pool: 'cluster',
  template_name: 'path to template',
  customization_spec: {
    ipsettings: {
      dnsServerList: ['1.2.3.31','1.2.3.41']
    },
    :domain => 'local'
  }
  :ssh => {
    :user => 'root',
    :password => 'password',
    :paranoid => false,
  }
}

machine "my_machine_name" do
  run_list ['my_cookbook::default']
end

```

## Provision!

```
chef-client -z -o 'my_cookbook::provision'
```

This will use chef-zero and needs no chef server (only works for ssh). Note that chef-zero does not support berkshelf style cookbook dependency resolution. So this works if the cookbook in the machine's runlist has no external dependencies. If it needs to reach out to supermarket or another berkshelf API server, perform a `berks vendor` to pull down the dependencies first.

## Supported machine bootstrapping options

- `[:use_linked_clone]` - (true/false) great for testing but not recommended for production.
- `[:datacenter]` - Name of vsphere datacenter (*required*)
- `[:template_name]` - path to vmware template (can be template or a shutown vm) (*required*)
- `[:vm_folder]` - path to a folder where the machine will be created.
- `[:datastore]` - name of datastore to use
- `[:num_cpus]` -  number of cpus to allocate to machine
- `[:network_name]` - array of network names to use. A NIC will be added for each
- `[:memory_mb]` - number of megabytes to allocate for machine
- `[:host]` - `{cluster}`/`{host}` to use during provisioning
- `[:resource_pool]` - `{cluster}`/`{resource pool}` to use during provisioning
- `[:additional_disk_size_gb] - if provided an additional disk will be added with the specified number of gigabytes (*his requires a datastore to be specified*)
- `[:ssh][:user]` user to use for ssh/winrm (defaults to root on linux/administrator on windows)
- `[:ssh][:password]` - password to use for ssh/winrm
- `[:ssh][:paranoid]` - specifies the strictness of the host key verification checking
- `[:ssh][:port]` port to use for ssh/winrm (defaults to 22 for ssh or 5985 for winrm)
- `[:convergence_options][:install_msi_url]` - url to chef client msi to use (defaults to latest) 
- `[:convergence_options][:install_sh_url]` - the bach script to install chef client on linux (defaults to latest)
- `[:customization_spec][:ipsettings][:ip]` static ip to assign to machine
- `[:customization_spec][:ipsettings][:subnetMask]` - subnet to use
- `[:customization_spec][:ipsettings][:gateway]` - gateway to use
- `[:customization_spec][:ipsettings][:dnsServerList]` - array of DNS servers to use
- `[:customization_spec][:domain]` - domain to use (if not 'local' on a windows machine it will attempt to domain join)
- `[:customization_spec][:domainAdmin]` - domain admin account to use for domain join on windows (should be `{user name}`@`{domain}`)
- `[:customization_spec][:domainAdminPassword]` - domain administrator password
- `[:customization_spec][:org_name]` - org name used in sysprep on windows
- `[:customization_spec][:product_id]` - windows product key
- `[:customization_spec][:win_time_zone]` - numeric time zone for windows

## More config examples

### Static IP and an additional 50GB disk

```
with_machine_options :bootstrap_options => {
  use_linked_clone: true,
  num_cpus: 2,
  memory_mb: 4096,
  network_name: ["vlan_20_172.21.20"],
  datacenter: 'datacenter_name',
  resource_pool: 'cluster',
  template_name: 'path to template',
  datastore: "my_data_store",
  additional_disk_size_gb: 50,
  customization_spec: {
    ipsettings: {
      ip: '192.168.3.4',
      subnetMask: '255.255.255.0',
      gateway: ["192.168.3.1"],
      dnsServerList: ['1.2.3.31','1.2.3.41']
    },
    :domain => 'local'
  }
  :ssh => {
    :user => 'root',
    :password => 'password',
    :paranoid => false,
  }
}
```

### Domain joined windows machine

Note: You must run chef-client against a server for a windows box. You cn do this locally since the provisioning recipe should not change the state of the provisioner. You will need to upload the cookbook (both the one doing the provisioning and the one used in the provisioned machine's runlist) before running `chef-client`.

```
with_machine_options :bootstrap_options => {
  use_linked_clone: true,
  num_cpus: 2,
  memory_mb: 4096,
  network_name: ["vlan_20_172.21.20"],
  datacenter: 'datacenter_name',
  resource_pool: 'cluster',
  template_name: 'path to template',
  customization_spec: {
    ipsettings: {
      dnsServerList: ['1.2.3.31','1.2.3.41']
    },
    domain => 'blah.com',
    domainAdmin => "administrator@blah.com",
    domainAdminPassword => "Passwordyoyoyo",
    org_name => 'acme',
    product_id => 'CDAA-87DC-3455-FF77-2AAC',
    win_time_zone => 4
  }
  :ssh => {
    :user => 'administrator',
    :password => 'password',
    :paranoid => false,
  }
}
```

## Contributions are welcome!

We took care to make this driver as generic as possible but there wll certainly be implementation nuances that may not work for everyone. We are happy to accept contributions to improve the driver and make it more accessible to a broader set of use cases.
