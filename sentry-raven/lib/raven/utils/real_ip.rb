require 'ipaddr'

# Based on ActionDispatch::RemoteIp. All security-related precautions from that
# middleware have been removed, because the Event IP just needs to be accurate,
# and spoofing an IP here only makes data inaccurate, not insecure. Don't re-use
# this module if you have to *trust* the IP address.
module Raven
  module Utils
    class RealIp
      LOCAL_ADDRESSES = [
        "127.0.0.1",      # localhost IPv4
        "::1",            # localhost IPv6
        "fc00::/7",       # private IPv6 range fc00::/7
        "10.0.0.0/8",     # private IPv4 range 10.x.x.x
        "172.16.0.0/12",  # private IPv4 range 172.16.0.0 .. 172.31.255.255
        "192.168.0.0/16" # private IPv4 range 192.168.x.x
      ].map { |proxy| IPAddr.new(proxy) }

      attr_accessor :ip, :ip_addresses

      def initialize(ip_addresses)
        self.ip_addresses = ip_addresses
      end

      def calculate_ip
        # CGI environment variable set by Rack
        remote_addr = ips_from(ip_addresses[:remote_addr]).last

        # Could be a CSV list and/or repeated headers that were concatenated.
        client_ips    = ips_from(ip_addresses[:client_ip])
        real_ips      = ips_from(ip_addresses[:real_ip])
        forwarded_ips = ips_from(ip_addresses[:forwarded_for])

        ips = [client_ips, real_ips, forwarded_ips, remote_addr].flatten.compact

        # If every single IP option is in the trusted list, just return REMOTE_ADDR
        self.ip = filter_local_addresses(ips).first || remote_addr
      end

      protected

      def ips_from(header)
        # Split the comma-separated list into an array of strings
        ips = header ? header.strip.split(/[,\s]+/) : []
        ips.select do |ip|
          begin
            # Only return IPs that are valid according to the IPAddr#new method
            range = IPAddr.new(ip).to_range
            # we want to make sure nobody is sneaking a netmask in
            range.begin == range.end
          rescue ArgumentError
            nil
          end
        end
      end

      def filter_local_addresses(ips)
        ips.reject { |ip| LOCAL_ADDRESSES.any? { |proxy| proxy === ip } }
      end
    end
  end
end
