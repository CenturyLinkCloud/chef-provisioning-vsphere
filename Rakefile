# frozen_string_literal: true
require 'bundler/gem_tasks'
require 'chef/provisioning/vsphere_driver/version'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

$LOAD_PATH.unshift(File.dirname(__FILE__) + '/lib')

RuboCop::RakeTask.new(:style) do |task|
  task.options << '--display-cop-names'
end

RSpec::Core::RakeTask.new(:unit) do |task|
  task.pattern = 'spec/unit_tests/*_spec.rb'
  task.rspec_opts = ['--color', '-f documentation']
end

RSpec::Core::RakeTask.new(:integration) do |task|
  task.pattern = 'spec/integration_tests/*_spec.rb'
  task.rspec_opts = ['--color', '-f documentation']
end

task default: [:unit]
