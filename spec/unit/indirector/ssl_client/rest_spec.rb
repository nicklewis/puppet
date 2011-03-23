#!/usr/bin/env ruby

require File.expand_path(File.dirname(__FILE__) + '/../../../spec_helper.rb')
require 'puppet/ssl/host'
require 'puppet/indirector/ssl_client'

describe "Puppet::SslClient::Rest" do
  before do
    @terminus = Puppet::SSL::Host.indirection.terminus(:rest)
  end

  it "should be a terminus on Puppet::SSL::Host" do
    @terminus.should be_instance_of(Puppet::Indirector::SslClient::Rest)
  end
end
