require 'chef_metal_vsphere/vsphere_provisioner'

ChefMetal.add_registered_provisioner_class('vsphere', ChefMetalVsphere::VsphereProvisioner)