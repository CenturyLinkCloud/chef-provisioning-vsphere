# frozen_string_literal: true
$LOAD_PATH.unshift(File.dirname(__FILE__) + '/lib')
require 'chef/provisioning/vsphere_driver/version'

Gem::Specification.new do |s|
  s.name = 'chef-provisioning-vsphere'
  s.version = ChefProvisioningVsphere::VERSION
  s.platform = Gem::Platform::RUBY
  s.extra_rdoc_files = ['README.md']
  s.summary = 'Provisioner for creating vSphere VM instances in Chef Provisioning.'
  s.description = s.summary
  s.authors = ['CenturyLink Cloud', 'JJ Asghar']
  s.email = 'jj@chef.io'
  s.homepage = 'https://github.com/chef-partners/chef-provisioning-vsphere'
  s.license = 'MIT'

  s.bindir       = 'bin'
  s.executables  = %w()

  s.require_path = 'lib'
  s.files        = `git ls-files -z`.split("\x0")
  s.test_files   = s.files.grep(%r{^(test|spec|features)/})

  s.add_dependency 'rbvmomi', '~> 1.8.0', '>= 1.8.2'
  s.add_dependency 'chef-provisioning', '~>2.0', '>= 2.0.1'
  s.add_dependency 'github_changelog_generator'

  s.add_development_dependency 'rspec'
  s.add_development_dependency 'rake'
  s.add_development_dependency 'chefstyle'
end
