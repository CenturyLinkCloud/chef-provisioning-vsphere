$:.unshift(File.dirname(__FILE__) + '/lib')
require 'chef_metal_vsphere/version'

Gem::Specification.new do |s|
  s.name = 'clc-chef-metal-vsphere'
  s.version = ChefMetalVsphere::VERSION
  s.platform = Gem::Platform::RUBY
  s.extra_rdoc_files = ['README.md']
  s.summary = 'Provisioner for creating vSphere VM instances in Chef Metal.'
  s.description = s.summary
  s.authors = ['CenturyLink Cloud']
  s.email = 'matt.wrock@CenturyLinkCloud.com'
  s.homepage = 'https://github.com/RallySoftware-cookbooks/chef-metal-vsphere'
  s.license = 'MIT'

  s.bindir       = 'bin'
  s.executables  = %w( )

  s.require_path = 'lib'
  s.files = %w(Rakefile README.md) + Dir.glob("{distro,lib,tasks,spec}/**/*", File::FNM_DOTMATCH).reject {|f| File.directory?(f) }

  s.add_dependency 'chef'
  s.add_dependency 'rbvmomi', '~> 1.5.1'
  s.add_dependency 'clc-fork-chef-metal', '0.11.2.alpha.3'

  s.add_development_dependency 'rspec'
  s.add_development_dependency 'rake'
end