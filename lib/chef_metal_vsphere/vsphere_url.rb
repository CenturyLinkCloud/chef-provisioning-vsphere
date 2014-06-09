require 'uri'

module URI
	class VsphereUrl < Generic
		DEFAULT_PORT = 443
		DEFAULT_PATH = '/sdk'

		def self.from_config(options)
			URI("vsphere://#{options[:host]}:#{options[:port]}#{options[:path]}?ssl=#{options[:ssl]}&insecure=#{options[:insecure]}")
		end

		def ssl
			if query
				ssl_query = query.split('&').each.first{|q| q.starts_wirh?('ssl=')}
				ssl_query == 'ssl=true'
			else
				true
			end
		end

		def insecure
			if query
				insecure_query = query.split('&').each.first{|q| q.starts_wirh?('insecure=')}
				insecure_query == 'insecure=true'
			else
				false
			end
		end
	end
	@@schemes['VSPHERE'] = VsphereUrl
end