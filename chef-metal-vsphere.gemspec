$:.unshift(File.dirname(__FILE__) + '/lib')
require 'chef_metal_vsphere/version'

Gem::Specification.new do |s|
  s.name = 'chef-metal-vsphere'
  s.version = ChefMetalVsphere::VERSION
  s.platform = Gem::Platform::RUBY
  s.extra_rdoc_files = ['README.md', 'LICENSE' ]
  s.summary = 'Provisioner for creating vSphere VM instances in Chef Metal.'
  s.description = s.summary
  s.author = 'Rally Software Development Corp'
  s.email = 'rallysoftware-cookbooks@rallydev.com'
  s.homepage = 'https://github.com/RallySoftware-cookbooks/chef-metal-vsphere'
  s.license = 'MIT'

  s.bindir       = 'bin'
  s.executables  = %w( )

  s.require_path = 'lib'
  s.files = %w(Rakefile LICENSE README.md) + Dir.glob("{distro,lib,tasks,spec}/**/*", File::FNM_DOTMATCH).reject {|f| File.directory?(f) }

  s.add_dependency 'chef'
  s.add_dependency 'rbvmomi'  # may need to lock nokogiri to 1.5.5

  s.add_development_dependency 'rspec'
  s.add_development_dependency 'rake'
end