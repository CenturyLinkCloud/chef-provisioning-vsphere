require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:unit) do |task|
  task.pattern = 'spec/unit_tests/*_spec.rb'
  task.rspec_opts = ['--color', '-f documentation']
end

RSpec::Core::RakeTask.new(:integration) do |task|
  task.pattern = 'spec/integration_tests/*_spec.rb'
  task.rspec_opts = ['--color', '-f documentation']
end

task :default => [:unit]
