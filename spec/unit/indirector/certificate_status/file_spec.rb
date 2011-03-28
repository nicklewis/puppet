#!/usr/bin/env ruby

require File.expand_path(File.dirname(__FILE__) + '/../../../spec_helper.rb')
require 'puppet/ssl/host'
require 'puppet/indirector/certificate_status'
require 'tempfile'

describe "Puppet::Indirector::CertificateStatus::File" do
  before do
    Puppet::SSL::CertificateAuthority.stubs(:ca?).returns true
    @terminus = Puppet::SSL::Host.indirection.terminus(:file)

    @tmpdir = Tempfile.new("certificate_status_ca_testing")
    @tmpdir.close
    File.unlink(@tmpdir.path)
    Dir.mkdir(@tmpdir.path)
    Puppet[:confdir] = @tmpdir.path
    Puppet[:vardir] = @tmpdir.path
  end

  it "should be a terminus on SSL::Host" do
    @terminus.should be_instance_of(Puppet::Indirector::CertificateStatus::File)
  end

  it "should create a CA instance if none is present" do
    @terminus.ca.should be_instance_of(Puppet::SSL::CertificateAuthority)
  end

  describe "when creating the CA" do
    it "should fail if it is not a valid CA" do
      Puppet::SSL::CertificateAuthority.expects(:ca?).returns false
      lambda { @terminus.ca }.should raise_error(ArgumentError)
    end
  end

  it "should be indirected with the name 'certificate_status'" do
    Puppet::SSL::Host.indirection.name.should == :certificate_status
  end

  describe "when saving" do
    before do
      @host = Puppet::SSL::Host.new("mysigner")
      @request = Puppet::Indirector::Request.new(:certificate_status, :save, "mysigner", @host)

      Puppet.settings.use(:main)
    end

    describe "and no CSR is provided and no CSR is on disk" do
      it "should fail" do
        lambda { @terminus.save(@request) }.should raise_error(ArgumentError, /certificate request/)
      end
    end

    describe "and a CSR is provided but none is on disk" do
      before do
        @host.generate_key

        csr = Puppet::SSL::CertificateRequest.new(@host.name)
        csr.generate(@host.key.content)
        @host.certificate_request = csr
      end

      it "should save the CSR and sign it" do
        Puppet::SSL::CertificateRequest.indirection.find("mysigner").should be_nil
        @terminus.save(@request)

        Puppet::SSL::Certificate.indirection.find("mysigner").should be_instance_of(
          Puppet::SSL::Certificate
        )
      end
    end

    describe "and a CSR is on disk and none is provided" do
      before do
        @host.generate_certificate_request
        @host.certificate_request = nil
      end

      it "should sign the on-disk CSR" do
        @host.certificate_request.class.indirection.save(@host.certificate_request)

        @terminus.save(@request)

        Puppet::SSL::Certificate.indirection.find("mysigner").should be_instance_of(Puppet::SSL::Certificate)
      end
    end

    describe "and a CSR is both on disk and provided" do
      it "should replace the on-disk CSR with any provided CSR and sign it" do
        @host.generate_certificate_request
        csr1 = @host.certificate_request

        # Generate a new cert request but *don't* save it to disk
        @host.key = nil
        @host.generate_key
        csr2 = Puppet::SSL::CertificateRequest.new(@host.name)
        csr2.generate(@host.key.content)
        @host.certificate_request = csr2

        @terminus.save(@request)

        cert = Puppet::SSL::Certificate.indirection.find("mysigner")
        cert.content.public_key.to_s.should_not == csr1.content.public_key.to_s
        cert.content.public_key.to_s.should == csr2.content.public_key.to_s
      end
    end
  end
end
