require 'chef/provisioning/vsphere_driver'

Chef::Provisioning.register_driver_class('vsphere', ChefProvisioningVsphere::VsphereDriver)