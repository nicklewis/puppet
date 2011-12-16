#!/usr/bin/env rspec
require 'spec_helper'

describe Puppet::Type.type(:service).provider(:init) do
  describe "when running on FreeBSD", :if => (Facter.value(:operatingsystem) == "FreeBSD") do
    it "should set its default path to include /etc/rc.d and /usr/local/etc/rc.d" do
      described_class.defpath.should == ["/etc/rc.d", "/usr/local/etc/rc.d"]
    end
  end

  describe "when running on HP-UX", :if => (Facter.value(:operatingsystem) == "HP-UX") do
    it "should set its default path to include /sbin/init.d" do
      described_class.defpath.should == "/sbin/init.d"
    end
  end

  describe "when running on Archlinux", :if => (Facter.value(:operatingsystem) == "Archlinux") do
    it "should set its default path to include /etc/rc.d" do
      described_class.defpath.should == "/etc/rc.d"
    end
  end

  describe "when not running on FreeBSD, HP-UX or Archlinux", :if => (! %w{HP-UX FreeBSD Archlinux}.include?(Facter.value(:operatingsystem))) do
    it "should set its default path to include /etc/init.d" do
      described_class.defpath.should == "/etc/init.d"
    end
  end
end
