module ChefProvisioningVsphere
  class CloneSpecBuilder
    def initialize(vsphere_helper, action_handler)
      @vsphere_helper = vsphere_helper
      @action_handler = action_handler
    end

    attr_reader :vsphere_helper
    attr_reader :action_handler

    def build(vm_template, vm_name, options)
      clone_spec = RbVmomi::VIM.VirtualMachineCloneSpec(
        location: relocate_spec_for(vm_template, options),
        powerOn: false,
        template: false,
        config: RbVmomi::VIM.VirtualMachineConfigSpec(
          :cpuHotAddEnabled => true,
          :memoryHotAddEnabled => true,
          :cpuHotRemoveEnabled => true,
          :deviceChange => Array.new)
      )

      unless options[:annotation].to_s.nil?
        clone_spec.config.annotation = options[:annotation]
      end

      unless options[:num_cpus].to_s.nil?
        clone_spec.config.numCPUs = options[:num_cpus]
      end

      unless options[:memory_mb].to_s.nil?
        clone_spec.config.memoryMB = options[:memory_mb]
      end

      unless options[:network_name].nil?
        deviceAdditions, changes = vsphere_helper.network_device_changes(
          action_handler,
          vm_template,
          options
        )
        clone_spec.config.deviceChange = changes
      end

      clone_spec.customization = customization_options_from(
        vm_template,
        vm_name,
        options
      )

      clone_spec
    end

    def relocate_spec_for(vm_template, options)
      rspec = RbVmomi::VIM.VirtualMachineRelocateSpec
      host = nil

      if options.has_key?(:host)
        host = vsphere_helper.find_host(options[:host])
        rspec.host = host
      end

      if options[:resource_pool]
        rspec.pool = vsphere_helper.find_pool(options[:resource_pool])
      elsif vm_template.config.template && !host.nil?
        rspec.pool = host.parent.resourcePool # assign to the "invisible" pool root
      elsif vm_template.config.template
        raise 'either :host or :resource_pool must be specified when cloning from a VM Template'
      end


      if options[:use_linked_clone]
        if vm_template.config.template
          Chef::Log.warn("Using a VM Template, ignoring use_linked_clone.")
        else
          vsphere_helper.create_delta_disk(vm_template)
          rspec.diskMoveType = :moveChildMostDiskBacking
        end
      end

      unless options[:datastore].to_s.empty?
        rspec.datastore = vsphere_helper.find_datastore(options[:datastore])
      end

      rspec
    end

    def customization_options_from(vm_template, vm_name, options)
      if options.has_key?(:customization_spec)
        if(options[:customization_spec].is_a?(Hash))
          cust_options = options[:customization_spec]
          ip_settings = cust_options[:ipsettings]
          cust_domain = cust_options[:domain]

          raise ArgumentError, 'domain is required' unless cust_domain
          cust_ip_settings = nil
          if ip_settings && ip_settings.key?(:ip)
            unless cust_options[:ipsettings].key?(:subnetMask)
              raise ArgumentError, 'subnetMask is required for static ip'
            end
            cust_ip_settings = RbVmomi::VIM::CustomizationIPSettings.new(
              ip_settings)
            action_handler.report_progress "customizing #{vm_name} \
              with static IP #{ip_settings[:ip]}"
            cust_ip_settings.ip = RbVmomi::VIM::CustomizationFixedIp(
              :ipAddress => ip_settings[:ip])
          end
          if cust_ip_settings.nil?
            cust_ip_settings= RbVmomi::VIM::CustomizationIPSettings.new(
              :ip => RbVmomi::VIM::CustomizationDhcpIpGenerator.new())
            cust_ip_settings.dnsServerList = ip_settings[:dnsServerList]
            action_handler.report_progress "customizing #{vm_name} with /
              dynamic IP and DNS: #{ip_settings[:dnsServerList]}"
          end

          cust_ip_settings.dnsDomain = cust_domain
          global_ip_settings = RbVmomi::VIM::CustomizationGlobalIPSettings.new
          global_ip_settings.dnsServerList = cust_ip_settings.dnsServerList
          global_ip_settings.dnsSuffixList = [cust_domain]
          cust_hostname = hostname_from(cust_options, vm_name)
          cust_hwclockutc = cust_options[:hw_clock_utc]
          cust_timezone = cust_options[:time_zone]

          if vm_template.config.guestId.start_with?('win')
            cust_prep = windows_prep_for(options, vm_name)
          else
            cust_prep = RbVmomi::VIM::CustomizationLinuxPrep.new(
              :domain => cust_domain,
              :hostName => cust_hostname,
              :hwClockUTC => cust_hwclockutc,
              :timeZone => cust_timezone
            )
          end
          cust_adapter_mapping = [
            RbVmomi::VIM::CustomizationAdapterMapping.new(
              :adapter => cust_ip_settings)
          ]
          RbVmomi::VIM::CustomizationSpec.new(
            :identity => cust_prep,
            :globalIPSettings => global_ip_settings,
            :nicSettingMap => cust_adapter_mapping
          )
        else
          vsphere_helper.find_customization_spec(cust_options)
        end
      end
    end

    def hostname_from(options, vm_name)
      hostname = options[:hostname] || vm_name
      test = /^([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])$/
      if !(hostname =~ test)
        raise 'Only letters, numbers or hyphens in hostnames allowed'
      end
      RbVmomi::VIM::CustomizationFixedName.new(:name => hostname)
    end

    def windows_prep_for(options, vm_name)
      cust_options = options[:customization_spec]
      cust_runonce = RbVmomi::VIM::CustomizationGuiRunOnce.new(
        :commandList => [
          'winrm set winrm/config/client/auth @{Basic="true"}',
          'winrm set winrm/config/service/auth @{Basic="true"}',
          'winrm set winrm/config/service @{AllowUnencrypted="true"}',
          'shutdown -l'])

      cust_login_password = RbVmomi::VIM::CustomizationPassword(
        :plainText => true,
        :value => options[:ssh][:password])
      if cust_options.has_key?(:domain) and cust_options[:domain] != 'local'
        cust_domain_password = RbVmomi::VIM::CustomizationPassword(
          :plainText => true,
          :value => ENV['domainAdminPassword'] || cust_options[:domainAdminPassword])
        cust_id = RbVmomi::VIM::CustomizationIdentification.new(
          :joinDomain => cust_options[:domain],
          :domainAdmin => cust_options[:domainAdmin],
          :domainAdminPassword => cust_domain_password)
        #puts "my env passwd is: #{ENV['domainAdminPassword']}"
        action_handler.report_progress "joining domain #{cust_options[:domain]} /
          with user: #{cust_options[:domainAdmin]}"
      else
        cust_id = RbVmomi::VIM::CustomizationIdentification.new(
          :joinWorkgroup => 'WORKGROUP')
      end
      cust_gui_unattended = RbVmomi::VIM::CustomizationGuiUnattended.new(
        :autoLogon => true,
        :autoLogonCount => 1,
        :password => cust_login_password,
        :timeZone => cust_options[:win_time_zone])
      cust_userdata = RbVmomi::VIM::CustomizationUserData.new(
        :computerName => hostname_from(cust_options, vm_name),
        :fullName => cust_options[:org_name],
        :orgName => cust_options[:org_name],
        :productId => cust_options[:product_id])
      RbVmomi::VIM::CustomizationSysprep.new(
        :guiRunOnce => cust_runonce,
        :identification => cust_id,
        :guiUnattended => cust_gui_unattended,
        :userData => cust_userdata)
    end
  end
end