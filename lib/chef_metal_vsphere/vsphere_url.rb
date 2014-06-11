require 'uri'

module URI
	class VsphereUrl < Generic
		DEFAULT_PORT = 443
		DEFAULT_PATH = '/sdk'

		def self.from_config(options)
			URI("vsphere://#{options[:host]}:#{options[:port]}#{options[:path]}?use_ssl=#{options[:use_ssl]}&insecure=#{options[:insecure]}")
		end

		def use_ssl
			if query
				ssl_query = query.split('&').each.select{|q| q.start_with?('use_ssl=')}.first
				ssl_query == 'use_ssl=true'
			else
				true
			end
		end

		def insecure
			if query
				insecure_query = query.split('&').each.select{|q| q.start_with?('insecure=')}.first
				insecure_query == 'insecure=true'
			else
				false
			end
		end
	end
	@@schemes['VSPHERE'] = VsphereUrl
end