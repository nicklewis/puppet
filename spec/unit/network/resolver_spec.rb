#!/usr/bin/env ruby
require File.dirname(__FILE__) + '/../../spec_helper'
require 'puppet/network/resolver'

describe Puppet::Network::Resolver do
  before do
    @dns_mock_object = mock('dns')
    Resolv::DNS.stubs(:new).returns(@dns_mock_object)

    @rr_type           = Resolv::DNS::Resource::IN::SRV
    @test_srv_hostname = "_puppet._tcp.domain.com"
    @test_a_hostname   = "puppet.domain.com"
    @test_port         = 1000

    # The records we should use.
    # priority, weight, port, hostname
    @test_records = [
      Resolv::DNS::Resource::IN::SRV.new(0, 20,  8140, "puppet1.domain.com"),
      Resolv::DNS::Resource::IN::SRV.new(0, 80,  8140, "puppet2.domain.com"),
      Resolv::DNS::Resource::IN::SRV.new(1, 1,   8140, "puppet3.domain.com"),
      Resolv::DNS::Resource::IN::SRV.new(4, 1,   8140, "puppet4.domain.com")
    ]
end


  describe "when resolving a host without SRV records" do
    it "should not yield anything" do

      # No records returned for a DNS entry without any SRV records
      @dns_mock_object.expects(:getresources).with(@test_a_hostname, @rr_type).returns([])

      Puppet::Network::Resolver.by_srv(@test_a_hostname) do |hostname, port, remaining|
        fail_with "host with no records passed block"
      end
    end
  end

  describe "when resolving a host with SRV records" do
    it "should iterate through records in priority order" do

      # The order of the records that should be returned,
      # an array means unordered (for weight)
      order = {
        0 => ["puppet1.domain.com", "puppet2.domain.com"],
        1 => ["puppet3.domain.com"],
        2 => ["puppet4.domain.com"]
      }

      @dns_mock_object.expects(:getresources).with(@test_srv_hostname, @rr_type).returns(@test_records)

      Puppet::Network::Resolver.by_srv(@test_srv_hostname) do |hostname, port|
        expected_priority = order.keys.min

        order[expected_priority].should include(hostname)
        port.should_not be(@test_port)

        # Remove the host from our expected hosts
        order[expected_priority].delete hostname

        # Remove this priority level if we're done with it
        order.delete expected_priority if order[expected_priority] == []
      end
    end
  end

  describe "when finding weighted servers" do
    it "should return nil when no records were found" do
      Puppet::Network::Resolver.find_weighted_server([]).should == nil
    end

    it "should return the first record when one record is passed" do
      result = Puppet::Network::Resolver.find_weighted_server([@test_records.first])
      result.should == @test_records.first
    end

    {
      "all have weights"  => [1, 3, 2, 4],
      "some have weights" => [2, 0, 1, 0],
      "none have weights" => [0, 0, 0, 0],
    }.each do |name, weights|
      it "should return correct results when #{name}" do
        records = []
        count   = 0
        weights.each do |w|
          # priority, weight, port, server
          count += 1
          records << Resolv::DNS::Resource::IN::SRV.new(0, w, 1, count.to_s)
        end

        seen  = Hash.new(0)
        total_weight = records.inject(0) { |sum, record|
          sum + (record.weight == 0 ? 1 : record.weight)
        }

        total_weight.times do |n|
          Kernel.expects(:rand).once.with(total_weight).returns(n)
          server = Puppet::Network::Resolver.find_weighted_server(records)
          seen[server] += 1
        end

        seen.length.should == records.length
        records.each do |record|
          seen[record].should == (record.weight == 0 ? 1 : record.weight)
        end
      end
    end
  end
end
