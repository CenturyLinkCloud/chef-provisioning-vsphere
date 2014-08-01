require 'kitchen/driver/vsphere_common'
require 'zip'

module Kitchen
  module Driver
    class VsphereWindows < Kitchen::Driver::WinRMBase

      default_config :machine_options,
        :start_timeout => 600,
        :create_timeout => 600,
        :ready_timeout => 90,
        :bootstrap_options => {
          :use_linked_clone => true,
          :ssh => {
            :user => 'administrator',
          },
          :convergence_options => {},
          :customization_spec => {
            :domain => 'local',
            :org_name => 'Tier3',
            :product_id => 'W3GGN-FT8W3-Y4M27-J84CP-Q3VJ9',
            :win_time_zone => 4
          }
        }
      
      attr_reader :connect_options

      include Kitchen::Driver::VsphereCommon
      include ChefMetalVsphere::Helpers

      def initialize(config = {})
        super

        @connect_options = config[:driver_options]
      end

      # We are overriding the stock test-kitchen winrm implementation
      # and leveraging vsphere's ability to upload files to the guest.
      # We zip, then send through vsphere and unzip over winrm
      def upload!(local, remote, winrm_connection)
        debug("Upload: #{local} -> #{remote}")
        if File.directory?(local)
          upload_directory(local, remote, winrm_connection)
        else
          upload_file(local, File.join(remote, File.basename(local)), winrm_connection)
        end
      end

      private

      def sanitize_path(path, connection)
        command = <<-EOH
          $dest_file_path = [System.IO.Path]::GetFullPath('#{path}')

          if (!(Test-Path $dest_file_path)) {
            $dest_dir = ([System.IO.Path]::GetDirectoryName($dest_file_path))
            New-Item -ItemType directory -Force -Path $dest_dir | Out-Null
          }

          $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("#{path}")
        EOH

        send_winrm(connection, command)
      end

      def upload_file(local, remote, connection)
        if connection.should_upload_file?(local, remote)
          remote = sanitize_path(remote, connection).strip
          vm = vim.searchIndex.FindByIp(:ip => connection.hostname, :vmSearch => true)
          upload_file_to_vm(vm,connection.username, connection.options[:password], local, remote)
        end
      end

      def upload_directory(local, remote, connection)
        zipped = zip_path(local)
        return if !File.exist?(zipped)
        remote_zip = File.join(remote, File.basename(zipped))
        debug "uploading #{zipped} to #{remote_zip}"
        upload_file(zipped, remote_zip, connection)
        extract_zip(remote_zip, connection)
      end

      def extract_zip(remote_zip, connection)
        debug "extracting #{remote_zip} to #{remote_zip.gsub('/','\\').gsub('.zip','')}"
        command = <<-EOH
          $shellApplication = new-object -com shell.application 
          $zip_path = "$($env:systemDrive)#{remote_zip.gsub('/','\\')}"
          $zipPackage = $shellApplication.NameSpace($zip_path) 
          $dest_path = "$($env:systemDrive)#{remote_zip.gsub('/','\\').gsub('.zip','')}"
          mkdir $dest_path -ErrorAction SilentlyContinue
          $destinationFolder = $shellApplication.NameSpace($dest_path) 
          $destinationFolder.CopyHere($zipPackage.Items(),0x10)
          Remove-Item $zip_path
        EOH

        send_winrm(connection, command)
      end

      def zip_path(path)
        path.sub!(%r[/$],'')
        archive = File.join(path,File.basename(path))+'.zip'
        FileUtils.rm archive, :force=>true

        Zip::File.open(archive, 'w') do |zipfile|
          Dir["#{path}/**/**"].reject{|f|f==archive}.each do |file|
            zipfile.add(file.sub(path+'/',''),file)
          end
        end

        archive
      end

      def send_winrm(connection, command)
        cmd = connection.powershell("$ProgressPreference='SilentlyContinue';" + command)
        stdout = (cmd[:data].map {|out| out[:stdout]}).join
        stderr = (cmd[:data].map {|out| out[:stderr]}).join

        if cmd[:exitcode] != 0 || ! stderr.empty?
          raise WinRMFailed,
            "WinRM exited (#{cmd[:exitcode]}) for
              command: [#{command}]\nREMOTE ERROR:\n" +
              stderr
        end

        stdout
      end
    end
  end
end
