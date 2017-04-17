# frozen_string_literal: true
require 'uri'

module URI
  class VsphereUrl < Generic
    DEFAULT_PORT = 443
    DEFAULT_PATH = '/sdk'

    def self.from_config(options)
      parts = []
      parts << 'vsphere://'
      parts << options[:host]
      parts << ':'
      parts << (options[:port] || DEFAULT_PORT)
      parts << (options[:path] || DEFAULT_PATH)
      parts << '?use_ssl='
      parts << (options[:use_ssl] == false ? false : true)
      parts << '&insecure='
      parts << (options[:insecure] || false)
      URI parts.join
    end

    def use_ssl
      if query
        ssl_query = query.split('&').each.select do |q|
          q.start_with?('use_ssl=')
        end.first
        ssl_query == 'use_ssl=true'
      else
        true
      end
    end

    def insecure
      if query
        insecure_query = query.split('&').each.select do |q|
          q.start_with?('insecure=')
        end.first
        insecure_query == 'insecure=true'
      else
        false
      end
    end
  end
  @@schemes['VSPHERE'] = VsphereUrl
end
