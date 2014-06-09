require_relative '../lib/chef_metal_vsphere/vsphere_url.rb'

describe 'VsphereUrl' do
	expected_host='1.1.1.1'
	expected_port=1818
	expected_path='/path'

	let(:url) {URI("vsphere://#{expected_host}:#{expected_port}#{expected_path}")}

	it "has the vsphere scheme" do
		expect(url.scheme).to eq('vsphere')
	end
	it "has the expected host" do
		expect(url.host).to eq(expected_host)
	end
	it "has the expected port" do
		expect(url.port).to eq(expected_port)
	end
	it "has the expected path" do
		expect(url.path).to eq(expected_path)
	end
	it "has the the default ssl setting" do
		expect(url.ssl).to eq(true)
	end
	it "has the the default insecure setting" do
		expect(url.insecure).to eq(false)
	end

	context "when setting from a hash" do
		let(:url) {URI::VsphereUrl.from_config({:host => '2.2.2.2', :port => 2345, :path => "/hoooo", :ssl => false, :insecure => true})}

		it "asigns the correct url" do
			expect(url.to_s).to eq('vsphere://2.2.2.2:2345/hoooo?ssl=false&insecure=true')
		end
	end
	context "when ssl is enabled" do
		it "retuns an ssl value of true" do
			url = URI("vsphere://#{expected_host}:#{expected_port}#{expected_path}?ssl=true")
			expect(url.ssl).to eq(true)
		end
	end
	context "when ssl is disabled" do
		it "retuns an ssl value of true" do
			url = URI("vsphere://#{expected_host}:#{expected_port}#{expected_path}?ssl=false")
			expect(url.ssl).to eq(false)
		end
	end
	context "when insecure is enabled" do
		it "retuns an insecure value of true" do
			url = URI("vsphere://#{expected_host}:#{expected_port}#{expected_path}?insecure=true")
			expect(url.insecure).to eq(true)
		end
	end
	context "when insecure is disabled" do
		it "retuns an insecure value of true" do
			url = URI("vsphere://#{expected_host}:#{expected_port}#{expected_path}?insecure=false")
			expect(url.insecure).to eq(false)
		end
	end
end