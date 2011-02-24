require 'net/http'
require 'uri'

require 'puppet/network/http_pool'
require 'puppet/network/http/api/v1'
require 'puppet/network/http/compression'
require 'puppet/network/resolver'

# Access objects via REST
class Puppet::Indirector::REST < Puppet::Indirector::Terminus
  include Puppet::Network::HTTP::API::V1
  include Puppet::Network::HTTP::Compression.module

  class << self
    attr_reader :server_setting, :port_setting
  end

  # Specify the setting that we should use to get the server name.
  def self.use_server_setting(setting)
    @server_setting = setting
  end

  def self.server
    Puppet.settings[server_setting || :server]
  end

  # Specify the setting that we should use to get the port.
  def self.use_port_setting(setting)
    @port_setting = setting
  end

  def self.port
    Puppet.settings[port_setting || :masterport].to_i
  end

  def resolve_servers_for(request)
    if !Puppet.settings[:use_srv_records] or request.server or self.class.server_setting or self.class.port_setting
      request.server ||= self.class.server
      request.port ||= self.class.port
      return yield request
    end

    # Finally, find a working SRV record, if none ...
    Puppet::Network::Resolver.each_srv_record(Puppet.settings[:srv_record]) do |srv_server, srv_port|
      begin
        request.server = srv_server
        request.port   = srv_port
        return yield request
      rescue SystemCallError => e
        Puppet.warning "Error connecting to #{srv_server}:#{srv_port}: #{e.message}"
      end
    end

    # ... Fall back onto the default server.
    Puppet.debug "No more servers left, falling back to #{self.class.server}"
    request.server = self.class.server
    request.port = self.class.port
    return yield request
  end

  # Figure out the content type, turn that into a format, and use the format
  # to extract the body of the response.
  def deserialize(response, multiple = false)
    case response.code
    when "404"
      return nil
    when /^2/
      raise "No content type in http response; cannot parse" unless response['content-type']

      content_type = response['content-type'].gsub(/\s*;.*$/,'') # strip any appended charset

      body = uncompress_body(response)

      # Convert the response to a deserialized object.
      if multiple
        model.convert_from_multiple(content_type, body)
      else
        model.convert_from(content_type, body)
      end
    else
      # Raise the http error if we didn't get a 'success' of some kind.
      raise convert_to_http_error(response)
    end
  end

  def convert_to_http_error(response)
    message = "Error #{response.code} on SERVER: #{(response.body||'').empty? ? response.message : uncompress_body(response)}"
    Net::HTTPError.new(message, response)
  end

  # Provide appropriate headers.
  def headers
    add_accept_encoding({"Accept" => model.supported_formats.join(", ")})
  end

  def network(request)
    Puppet::Network::HttpPool.http_instance(request.server || self.class.server, request.port || self.class.port)
  end

  def find(request)
    result = resolve_servers_for(request) do |request|
      deserialize(network(request).get(indirection2uri(request), headers))
    end

    return nil unless result
    result.name = request.key if result.respond_to?(:name=)
    result
  end

  def head(request)
    response = resolve_servers_for(request) do |request|
      network(request).head(indirection2uri(request), headers)
    end

    case response.code
    when "404"
      return false
    when /^2/
      return true
    else
      # Raise the http error if we didn't get a 'success' of some kind.
      raise convert_to_http_error(response)
    end
  end

  def search(request)
    result = resolve_servers_for(request) do |request|
      deserialize(network(request).get(indirection2uri(request), headers), true)
    end

    # result from the server can be nil, but we promise to return an array...
    result || []
  end

  def destroy(request)
    raise ArgumentError, "DELETE does not accept options" unless request.options.empty?

    resolve_servers_for(request) do |request|
      deserialize network(request).delete(indirection2uri(request), headers)
    end
  end

  def save(request)
    raise ArgumentError, "PUT does not accept options" unless request.options.empty?

    resolve_servers_for(request) do |request|
      deserialize network(request).put(indirection2uri(request), request.instance.render, headers.merge({ "Content-Type" => request.instance.mime }))
    end
  end

  private

  def environment
    Puppet::Node::Environment.new
  end
end
