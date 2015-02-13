require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

$:.unshift(File.dirname(__FILE__) + '/lib')
require 'chef_metal_vsphere/version'

module Bundler
  class GemHelper
    def rubygem_push(path)
      gem_file = File.join(
        File.dirname(__FILE__), "pkg", 
        "chef-metal-vsphere-#{ChefMetalVsphere::VERSION}.gem"
      )
      puts "pushing #{gem_file}"
      system("gem nexus '#{gem_file}'")
      system("gem push '#{gem_file}'")
    end
  end
end

RSpec::Core::RakeTask.new(:unit) do |task|
  task.pattern = 'spec/unit_tests/*_spec.rb'
  task.rspec_opts = ['--color', '-f documentation']
end

RSpec::Core::RakeTask.new(:integration) do |task|
  task.pattern = 'spec/integration_tests/*_spec.rb'
  task.rspec_opts = ['--color', '-f documentation']
end

task :default => [:unit]
