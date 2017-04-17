# frozen_string_literal: true
module ChefProvisioningVsphereStubs
  class FakeActionHandler < Chef::Provisioning::ActionHandler
    def puts(out); end
  end
end
