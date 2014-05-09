require 'bundler'
require 'bundler/gem_tasks'

def gem_server
  @gem_server ||= ENV['GEM_SERVER'] || 'rubygems.org'
end

module Bundler
  class GemHelper
    unless gem_server == 'rubygems.org'
      unless method_defined?(:rubygem_push)
        raise NoMethodError, "Monkey patching Bundler::GemHelper#rubygem_push failed: did the Bundler API change???"
      end

      def rubygem_push(path)
        print "Username: "
        username = STDIN.gets.chomp
        print "Password: "
        password = STDIN.gets.chomp

        gem_server_url = "https://#{username}:#{password}@#{gem_server}/"
        sh %{gem push #{path} --host #{gem_server_url}}

        Bundler.ui.confirm "Pushed #{name} #{version} to #{gem_server}"
      end

      puts "Monkey patched Bundler::GemHelper#rubygem_push to push to #{gem_server}."
    end
  end
end