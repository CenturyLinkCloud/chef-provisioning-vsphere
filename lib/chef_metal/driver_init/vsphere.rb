require 'chef_metal_vsphere/vsphere_driver'

ChefMetal.register_driver_class('vsphere', ChefMetalVsphere::VsphereDriver)