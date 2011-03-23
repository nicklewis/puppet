require 'puppet/ssl/host'
require 'puppet/indirector/rest'
require 'puppet/indirector/ssl_client'

class Puppet::Indirector::SslClient::Rest < Puppet::Indirector::REST
  desc "Sign certificate requests over HTTP via REST."

  use_server_setting(:ca_server)
  use_port_setting(:ca_port)
end
