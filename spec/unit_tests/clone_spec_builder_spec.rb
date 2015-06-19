require 'chef/provisioning/vsphere_driver'
require_relative 'support/fake_action_handler'
require_relative 'support/vsphere_helper_stub'

describe ChefProvisioningVsphere::CloneSpecBuilder do
  let(:options) { Hash.new }
  let(:vm_template) { double('template') }

  before do
    allow(vm_template).to receive_message_chain(:config, :guestId)
      .and_return('guest')
    allow(vm_template).to receive_message_chain(:config, :template)
      .and_return(false)
  end

  subject do
    builder = ChefProvisioningVsphere::CloneSpecBuilder.new(
      ChefProvisioningVsphereStubs::VsphereHelperStub.new,
      ChefProvisioningVsphereStubs::FakeActionHandler.new
    )
    builder.build(vm_template, 'machine_name', options)
  end

  context 'using linked clones' do
    before { options[:use_linked_clone] = true }

    it 'sets the disk move type of the relocation spec' do
      expect(subject.location.diskMoveType).to be :moveChildMostDiskBacking
    end
  end

  context 'using linked clone on a template source' do
    before do
      options[:use_linked_clone] = true
      options[:host] = 'host'
      allow(vm_template).to receive_message_chain(:config, :template)
        .and_return(true)
    end

    it 'does not set the disk move type of the relocation spec' do
      expect(subject.location.diskMoveType).to be nil
    end
  end

  context 'not using linked clones' do
    before { options[:use_linked_clone] = false }

    it 'does not set the disk move type of the relocation spec' do
      expect(subject.location.diskMoveType).to be nil
    end
  end

  context 'specifying a host' do
    before { options[:host] = 'host' }

    it 'sets the host' do
      expect(subject.location.host).to_not be nil
    end
  end

  context 'not specifying a host' do
    it 'does not set the host' do
      expect(subject.location.host).to be nil
    end
  end

  context 'specifying a pool' do
    before { options[:resource_pool] = 'pool' }

    it 'sets the pool' do
      expect(subject.location.pool).to_not be nil
    end
  end

  context 'not specifying a pool' do
    it 'does not set the pool' do
      expect(subject.location.pool).to be nil
    end
  end

  context 'not specifying a pool but specifying a host on a template' do
    before do 
      options[:host] = 'host'
      allow(vm_template).to receive_message_chain(:config, :template)
        .and_return(true)
    end

    it 'sets the pool to the hosts parent root pool' do
      expect(subject.location.pool).to be subject.location.host.parent.resourcePool
    end
  end

  context 'not specifying a pool or host when cloning from a template' do
    before do
      allow(vm_template).to receive_message_chain(:config, :template)
        .and_return(true)
    end

    it 'raises an error' do
      expect { subject }.to raise_error
    end
  end

  context 'specifying a hostname' do
    before do
      options[:customization_spec] = { 
        ipsettings: {},
        hostname: hostname,
        domain: 'local' 
      }
    end

    context 'alpha characters only' do
      let(:hostname) { 'myhost' }

      it 'sets the spec hostname' do
        expect(subject.customization.identity.hostName.name).to eq hostname
      end
    end

    context 'alpha numeric characters only' do
      let(:hostname) { 'myhost01' }

      it 'sets the spec hostname' do
        expect(subject.customization.identity.hostName.name).to eq hostname
      end
    end

    context 'containing a dash' do
      let(:hostname) { 'my-host01' }

      it 'sets the spec hostname' do
        expect(subject.customization.identity.hostName.name).to eq hostname
      end
    end

    context 'containing an underscore' do
      let(:hostname) { 'my_host' }

      it 'raises an error' do
        expect { subject }.to raise_error
      end
    end

    context 'starting with a dash' do
      let(:hostname) { '-myhost' }

      it 'raises an error' do
        expect { subject }.to raise_error
      end
    end

    context 'ending with a dash' do
      let(:hostname) { 'myhost-' }

      it 'raises an error' do
        expect { subject }.to raise_error
      end
    end    
  end
end
