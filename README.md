# chef-provisioning-vsphere

[![Gem Version](https://img.shields.io/gem/v/chef-provisioning-vsphere.svg)][gem]
[![Build Status](https://travis-ci.org/chef-partners/chef-provisioning-vsphere.svg?branch=master)][travis]

This is a [chef-provisioning](https://github.com/chef/chef-provisioning) provisioner for [VMware vSphere](http://www.vmware.com/products/vsphere).

chef-provisioning-vsphere supports provisioning Unix/ssh and Windows/WinRMrm guest VMs.

## Prerequisites

### vSphere infrastructure

A vCenter and valid login credentials.

### VM Template

A VM template capable of installing Chef 11.8 or newer. This can be either windows or linux flavored.

### A provisioning node (can be local)

An environment equipped with the `chef-client` and the `chef-provisioning-vsphere` gem.

## A basic provisioning recipe

This is a minimal machine definition that will use a dhcp assigned ip (it assumes the presense of a dhcp server). For test purposes this uses a linked clone for a faster provisioning time. This recipe should be used with a linux template. Windows provisioned servers need to point to a chef server for the cookbooks since winrm does not support port forwarding and there fore cannot reach back on the chef-zero port to get the local cookbooks. See examples below.

```ruby
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

```shell
$ chef-client -z -o 'my_cookbook::provision'
```

This will use chef-zero and needs no chef server (only works for ssh). Note that chef-zero does not support berkshelf style cookbook dependency resolution. So this works if the cookbook in the machine's runlist has no external dependencies. If it needs to reach out to supermarket or another berkshelf API server, perform a `berks vendor` to pull down the dependencies first.

## Supported machine bootstrapping options

- `[:use_linked_clone]` - (true/false) great for testing but not recommended for production.
- `[:datacenter]` - Name of vsphere datacenter (*required*)
- `[:template_name]` - path to vmware template (can be template or a shutown vm) (*required*)
- `[:template_folder]` - path to a folder containing the template (do not use if template is in the root vm folder)
- `[:vm_folder]` - path to a folder where the machine will be created.
- `[:datastore]` - name of datastore to use
- `[:num_cpus]` -  number of cpus to allocate to machine
- `[:network_name]` - array of network names to use. A NIC will be added for each
- `[:memory_mb]` - number of megabytes to allocate for machine
- `[:host]` - `{cluster}`/`{host}` to use during provisioning
- `[:resource_pool]` - `{cluster}`/`{resource pool}` to use during provisioning
- `[:additional_disk_size_gb]` - an array of numbers, each signifying the number of gigabytes to assign to an additional disk (*this requires a datastore to be specified*)
- `[:bootstrap_ipv4]` - `true` / `false`, set to `true` to wait for an IPv4 address to become available before bootstrapping.
- `[:ipv4_timeout]` - use with `[:bootstrap_ipv4]`, set the time in seconds to wait before an IPv4 address is received (defaults to 30)
- `[:ssh][:user]` user to use for ssh/winrm (defaults to root on linux/administrator on windows)
- `[:ssh][:password]` - password to use for ssh/winrm
- `[:ssh][:paranoid]` - specifies the strictness of the host key verification checking
- `[:ssh][:port]` port to use for ssh/winrm (defaults to 22 for ssh or 5985 for winrm)
- `[:convergence_options][:install_msi_url]` - url to chef client msi to use (defaults to latest)
- `[:convergence_options][:install_sh_url]` - the bash script to install chef client on linux (defaults to latest)
- `[:customization_spec][:ipsettings][:ip]` static ip to assign to machine
- `[:customization_spec][:ipsettings][:subnetMask]` - subnet to use
- `[:customization_spec][:ipsettings][:gateway]` - array of possible gateways to use (this will most often be an array of 1)
- `[:customization_spec][:ipsettings][:dnsServerList]` - array of DNS servers to use
- `[:customization_spec][:domain]` - domain to use (if not 'local' on a windows machine it will attempt to domain join)
- `[:customization_spec][:domainAdmin]` - domain admin account to use for domain join on windows (should be `{user name}`@`{domain}`)
- `[:customization_spec][:domainAdminPassword]` - domain administrator password
- `[:customization_spec][:hostname]` - hostname to use. Defaults to machine resource name if not provided
- `[:customization_spec][:org_name]` - org name used in sysprep on windows
- `[:customization_spec][:product_id]` - windows product key
- `[:customization_spec][:run_once]` - Array of commands for vSphere to run at the end of windows bootstrapping
- `[:customization_spec][:time_zone]` - The case-sensitive timezone, such as Europe/Sofia based on the tz (timezone) database used by Linux and other Unix systems
- `[:customization_spec][:winrm_transport]` - winrm transport to use. Defaults to `negotiate`
- `[:customization_spec][:win_time_zone]` - numeric time zone for windows
- `[:customization_spec][:winrm_opts]` - Optional hash of [winrm options](https://github.com/WinRb/WinRM) (e.g. `disable_sspi: true`)

## Timeout options
These are settings set at the root of `machine_options`. Chances are the defaults for these settings do not need to be changed:

- `start_timeout` - number of seconds to wait for a machine to be accessible after a restart (default 10 minutes)
- `create_timeout` - number of seconds to wait for a machine to be accessible after initiating provisioning (default 10 minutes)
- `ready_timeout` - number of seconds to wait for customization to complete and vmware tools to come on line (default 5 minutes)

## More config examples

### Static IP and two additional disks of 20 and 50GB

```ruby
with_machine_options :bootstrap_options => {
  use_linked_clone: true,
  num_cpus: 2,
  memory_mb: 4096,
  network_name: ["vlan_20_172.21.20"],
  datacenter: 'datacenter_name',
  resource_pool: 'cluster',
  template_name: 'path to template',
  datastore: "my_data_store",
  additional_disk_size_gb: [50,20],
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
NOTE: customization_spec `org_name` and `product_id` are required for sysprep Windows machines.

```ruby
with_machine_options :bootstrap_options => {
  use_linked_clone: true,
  num_cpus: 2,
  memory_mb: 4096,
  network_name: ['vlan_20_172.21.20'],
  datacenter: 'datacenter_name',
  resource_pool: 'cluster',
  template_name: 'path to template',
  customization_spec: {
    ipsettings: {
      dnsServerList: ['1.2.3.31','1.2.3.41']
    },
    domain: 'blah.com',
    domainAdmin: 'administrator@blah.com',
    domainAdminPassword: 'Passwordyoyoyo',
    org_name: 'acme',
    product_id: 'CDAA-87DC-3455-FF77-2AAC',
    win_time_zone: 4
  }
  ssh: {
    user: 'administrator',
    password: 'password',
    paranoid: false,
  }
},
:convergence_options => {
  :ssl_verify_mode => :verify_none
}
```

Note: You must run chef-client against a server for a windows box. You can do this locally since the provisioning recipe should not change the state of the provisioner. You will need to upload the cookbook (both the one doing the provisioning and the one used in the provisioned machine's runlist) before running `chef-client`.

```shell
$ knife cookbook upload my_cookbook
$ chef-client -o 'my_cookbook::provision' -c .chef/knife.rb
```

### Prefix all SSH commands with 'sudo ', for installing on hosts where options[:bootstrap_options][:ssh][:user] is not 'root'. The user must have 'NOPASSWD:ALL' in /etc/sudoers. This is compatible with chef-provisioning-fog functionality

```ruby
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
},
:sudo => true

machine "my_machine_name" do
  run_list ['my_cookbook::default']
end

```
## Kitchen Driver

This chef-provisioning-driver comes with a test-kitchen driver. Here are example driver options you can add to your `kitchen.yml`.

```yaml
driver:
  name: vsphere
  driver_options:
    host: '1.2.3.5'
    user: 'user'
    password: 'pass'
    insecure: true
  machine_options:
    start_timeout: 600
    create_timeout: 600
    ready_timeout: 90
    bootstrap_options:
      use_linked_clone: true
      datacenter: 'DC'
      template_name: 'UBUNTU1264'
      vm_folder: 'TEST'
      num_cpus: 2,
      network_name:
        - vlan_20_1.2.3.4
      memory_mb: 4096
      resource_pool: 'CLSTR/TEST'
      ssh:
        user: root
        paranoid: false
        password: password
        port: 22
      convergence_options:
      customization_spec:
        domain: local
        ipsettings:
          dnsServerList:
            - 8.8.8.8
            - 8.8.4.4
```

You can also spin up multiple nodes, overwriting driver settings by platform or suite.

```yaml
driver:
  name: vsphere
  driver_options:
    host: '1.2.3.5'
    user: 'user'
    password: 'pass'
    insecure: true
  machine_options:
    start_timeout: 600
    create_timeout: 600
    ready_timeout: 90
    bootstrap_options:
      use_linked_clone: true
      datacenter: 'DC'
      template_name: 'UBUNTU1264'
      vm_folder: 'TEST'
      num_cpus: 2,
      network_name:
        - vlan_20_1.2.3.4
      memory_mb: 4096
      resource_pool: 'CLSTR/TEST'
      ssh:
        user: root
        paranoid: false
        password: password
        port: 22
      convergence_options:
      customization_spec:
        domain: local
        ipsettings:
          dnsServerList:
            - 8.8.8.8
            - 8.8.4.4

platforms:
  - name: one_disk
  - name: two_disk
    driver:
      machine_options:
        bootstrap_options:
          additional_disk_size_gb:
            - 10
            - 10
            - 10
            - 10
            
suites:
  - name: default
    runlist:
      - recipe[mycookbook::default]
  - name: memory-intensive
    runlist:
      - recipe[mycookbook::intense]
    driver:
      machine_options:
        bootstrap_options:
          memory_mb: 8192

```

You can run then `kitchen diagnose` to verify the nodes and settings that will be used when you call `kitchen create`.

## Contributing

1. Fork it ( https://github.com/[my-github-username]/chef-provisioning-vsphere/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

[gem]: https://rubygems.org/gems/chef-provisioning-vsphere
[travis]: https://travis-ci.org/chef-partners/chef-provisioning-vsphere
