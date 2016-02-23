#
# Author::
# Copyright:: Copyright (c) 2016 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'azure/azure_interface'
require 'azure/service_management/rest'
require 'azure/service_management/connection'

module Azure
  class ServiceManagement
    class ASMInterface < AzureInterface
      include AzureAPI

      attr_accessor :connection

      def initialize(params = {})
        @rest = Rest.new(params)
        @connection = Azure::ServiceManagement::Connection.new(@rest)
        super
      end

      def list_images
        connection.images.all
      end

      def list_servers
        servers = connection.roles.all
        cols = ['DNS Name', 'VM Name', 'Status', 'IP Address', 'SSH Port', 'WinRM Port' ]
        rows = []
        servers.each do |server|
          rows << server.hostedservicename.to_s+".cloudapp.net"  # Info about the DNS name at http://msdn.microsoft.com/en-us/library/ee460806.aspx
          rows << server.name.to_s
          rows << begin
                           state = server.status.to_s.downcase
                           case state
                           when 'shutting-down','terminated','stopping','stopped'
                             ui.color(state, :red)
                           when 'pending'
                             ui.color(state, :yellow)
                           else
                             ui.color('ready', :green)
                           end
                         end
          rows << server.publicipaddress.to_s
          rows << server.sshport.to_s
          rows << server.winrmport.to_s
        end
        display_list(ui, cols, rows)
      end

      def find_server(params = {})
        server = connection.roles.find(params[:name], params = { :azure_dns_name => params[:azure_dns_name] })
      end

      def delete_server(params = {})
        server = find_server({name: params[:name], azure_dns_name: params[:azure_dns_name]})

        if not server
          ui.warn("Server #{name} does not exist")
          return
        end

        puts "\n"
        msg_pair(ui, 'DNS Name', server.hostedservicename + ".cloudapp.net")
        msg_pair(ui, 'VM Name', server.name)
        msg_pair(ui, 'Size', server.size)
        msg_pair(ui, 'Public Ip Address', server.publicipaddress)
        puts "\n"

        begin
          confirm("Do you really want to delete this server")
        rescue SystemExit   # Need to handle this as confirming with N/n raises SystemExit exception
          server = nil      # Cleanup is implicitly performed in other cloud plugins
          exit!
        end

        connection.roles.delete(params)


        puts '\n'
        ui.warn("Deleted server #{server.name}")
      end

      def show_server name
        connection.roles.find name
      end

      def list_internal_lb
        lbs = connection.lbs.all
        cols = %w{Name Service Subnet VIP}
        rows = []
        lbs.each do |lb|
          cols.each { |col| rows << lb.send(col.downcase).to_s }
        end
        display_list(ui, cols, rows)
      end

      def create_internal_lb(params = {})
        connection.lbs.create(params)
      end

      def list_vnets
        vnets = connection.vnets.all
        cols = ['Name', 'Affinity Group', 'State']
        rows = []
        vnets.each do |vnet|
          %w(name affinity_group state).each{ |col| rows << vnet.send(col).to_s }
        end
        display_list(ui, cols, rows)
      end

      def create_vnet(params = {})
        connection.vnets.create(params)
      end

      def list_affinity_groups
        affinity_groups = connection.ags.all
        cols = %w{Name Location Description}
        rows = []
        affinity_groups.each do |affinity_group|
          cols.each { |col| rows << affinity_group.send(col.downcase).to_s }
        end
        display_list(ui, cols, rows)
      end

      def create_affinity_group(params = {})
        connection.ags.create(params)
      end

      def create_server(params = {})
        remove_hosted_service_on_failure = params[:azure_dns_name]
        if connection.hosts.exists?(params[:azure_dns_name])
          remove_hosted_service_on_failure = nil
        end

        #If Storage Account is not specified, check if the geographic location has one to re-use
        if not params[:azure_storage_account]
          storage_accts = connection.storageaccounts.all
          storage = storage_accts.find { |storage_acct| storage_acct.location.to_s == params[:azure_service_location] }
          unless storage
            params[:azure_storage_account] = [strip_non_ascii(params[:azure_vm_name]), random_string].join.downcase
            remove_storage_service_on_failure = params[:azure_storage_account]
          else
            remove_storage_service_on_failure = nil
            params[:azure_storage_account] = storage.name.to_s
          end
        else
          if connection.storageaccounts.exists?(params[:azure_storage_account])
            remove_storage_service_on_failure = nil
          else
            remove_storage_service_on_failure = params[:azure_storage_account]
          end
        end

        begin
          connection.deploys.create(params)
        rescue Exception => e
          Chef::Log.error("Failed to create the server -- exception being rescued: #{e.to_s}")
          backtrace_message = "#{e.class}: #{e}\n#{e.backtrace.join("\n")}"
          Chef::Log.debug("#{backtrace_message}")
          cleanup_and_exit(remove_hosted_service_on_failure, remove_storage_service_on_failure)
        end

      end

      def cleanup_and_exit(remove_hosted_service_on_failure, remove_storage_service_on_failure)
        Chef::Log.warn("Cleaning up resources...")

        if remove_hosted_service_on_failure
          ret_val = connection.hosts.delete(remove_hosted_service_on_failure)
          ret_val.content.empty? ? Chef::Log.warn("Deleted created DNS: #{remove_hosted_service_on_failure}.") : Chef::Log.warn("Deletion failed for created DNS:#{remove_hosted_service_on_failure}. " + ret_val.text)
        end

        if remove_storage_service_on_failure
          ret_val = connection.storageaccounts.delete(remove_storage_service_on_failure)
          ret_val.content.empty? ? Chef::Log.warn("Deleted created Storage Account: #{remove_storage_service_on_failure}.") : Chef::Log.warn("Deletion failed for created Storage Account: #{remove_storage_service_on_failure}. " + ret_val.text)
        end
        exit 1
      end

       def get_role_server(dns_name, vm_name)
        deploy = connection.deploys.queryDeploy(dns_name)
        deploy.find_role(vm_name)
      end

      def get_extension(name, publisher)
        connection.query_azure("resourceextensions/#{publisher}/#{name}")
      end

      def deployment_name(dns_name)
        connection.deploys.get_deploy_name_for_hostedservice(dns_name)
      end

      def deployment(path)
        connection.query_azure(path)
      end

      def valid_image?(name)
        connection.images.exists?(name)
      end

      def vm_image?(name)
        connection.images.is_vm_image(name)
      end
    end
  end
end

