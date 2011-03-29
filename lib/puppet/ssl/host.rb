require 'puppet/indirector'
require 'puppet/ssl'
require 'puppet/ssl/key'
require 'puppet/ssl/certificate'
require 'puppet/ssl/certificate_request'
require 'puppet/ssl/certificate_revocation_list'
require 'puppet/util/cacher'

# The class that manages all aspects of our SSL certificates --
# private keys, public keys, requests, etc.
class Puppet::SSL::Host
  # Yay, ruby's strange constant lookups.
  Key = Puppet::SSL::Key
  CA_NAME = Puppet::SSL::CA_NAME
  Certificate = Puppet::SSL::Certificate
  CertificateRequest = Puppet::SSL::CertificateRequest
  CertificateRevocationList = Puppet::SSL::CertificateRevocationList

  extend Puppet::Indirector
  indirects :certificate_status, :terminus_class => :file

  attr_reader :name
  attr_accessor :ca

  attr_writer :key, :certificate, :certificate_request

  attr_accessor :fingerprint, :message
  attr_reader :state

  CERT_STATES = %w{requested signed invoked invalid}

  class << self
    include Puppet::Util::Cacher

    cached_attr(:localhost) do
      result = new
      result.generate unless result.certificate
      result.key # Make sure it's read in
      result
    end
  end

  # This is the constant that people will use to mark that a given host is
  # a certificate authority.
  def self.ca_name
    CA_NAME
  end

  class << self
    attr_reader :ca_location
  end

  # Configure how our various classes interact with their various terminuses.
  def self.configure_indirection(terminus, cache = nil)
    Certificate.indirection.terminus_class = terminus
    CertificateRequest.indirection.terminus_class = terminus
    CertificateRevocationList.indirection.terminus_class = terminus

    host_map = {:ca => :file, :file => nil, :rest => :rest}
    if term = host_map[terminus]
      self.indirection.terminus_class = term
    else
      self.indirection.reset_terminus_class
    end

    if cache
      # This is weird; we don't actually cache our keys, we
      # use what would otherwise be the cache as our normal
      # terminus.
      Key.indirection.terminus_class = cache
    else
      Key.indirection.terminus_class = terminus
    end

    if cache
      Certificate.indirection.cache_class = cache
      CertificateRequest.indirection.cache_class = cache
      CertificateRevocationList.indirection.cache_class = cache
    else
      # Make sure we have no cache configured.  puppet master
      # switches the configurations around a bit, so it's important
      # that we specify the configs for absolutely everything, every
      # time.
      Certificate.indirection.cache_class = nil
      CertificateRequest.indirection.cache_class = nil
      CertificateRevocationList.indirection.cache_class = nil
    end
  end

  CA_MODES = {
    # Our ca is local, so we use it as the ultimate source of information
    # And we cache files locally.
    :local => [:ca, :file],
    # We're a remote CA client.
    :remote => [:rest, :file],
    # We are the CA, so we don't have read/write access to the normal certificates.
    :only => [:ca],
    # We have no CA, so we just look in the local file store.
    :none => [:file]
  }

  # Specify how we expect to interact with our certificate authority.
  def self.ca_location=(mode)
    modes = CA_MODES.collect { |m, vals| m.to_s }.join(", ")
    raise ArgumentError, "CA Mode can only be #{modes}" unless CA_MODES.include?(mode)

    @ca_location = mode

    configure_indirection(*CA_MODES[@ca_location])
  end

  # Puppet::SSL::Host is actually indirected now so the original implementation
  # has been moved into the certificate_status indirector.  This method is in-use
  # in `puppet cert -c <certname>`.
  def self.destroy(name)
    indirection.destroy(name)
  end

  def self.from_pson(pson)
    instance = new(pson["name"])
    if pson["certificate"]
      instance.certificate = Puppet::SSL::Certificate.from_s(
        pson["certificate"])
    end
    if pson["certificate_request"]
      instance.certificate_request = Puppet::SSL::CertificateRequest.from_s(
        pson["certificate_request"])
    end
    instance.fingerprint = pson["fingerprint"]
    instance.message = pson["message"]
    begin
      instance.state = pson["state"]
    rescue ArgumentError
    end
    instance
  end

  # Puppet::SSL::Host is actually indirected now so the original implementation
  # has been moved into the certificate_status indirector.  This method does not
  # appear to be in use in `puppet cert -l`.
  def self.search(options = {})
    indirection.search("*", options)
  end

  # Is this a ca host, meaning that all of its files go in the CA location?
  def ca?
    ca
  end

  def key
    @key ||= Key.indirection.find(name)
  end

  # This is the private key; we can create it from scratch
  # with no inputs.
  def generate_key
    @key = Key.new(name)
    @key.generate
    begin
      Key.indirection.save(@key)
    rescue
      @key = nil
      raise
    end
    true
  end

  def certificate_request
    @certificate_request ||= CertificateRequest.indirection.find(name)
  end

  # Our certificate request requires the key but that's all.
  def generate_certificate_request
    generate_key unless key
    @certificate_request = CertificateRequest.new(name)
    @certificate_request.generate(key.content)
    begin
      CertificateRequest.indirection.save(@certificate_request)
    rescue
      @certificate_request = nil
      raise
    end

    true
  end

  def certificate
    unless @certificate
      # get the CA cert first, since it's required for the normal cert
      # to be of any use.
      return nil unless Certificate.indirection.find("ca") unless ca?
      return nil unless @certificate = Certificate.indirection.find(name)

      generate_key unless key

      unless certificate_matches_key?
        raise Puppet::Error, "Retrieved certificate does not match private key; please remove certificate from server and regenerate it with the current key"
      end
    end
    @certificate
  end

  def certificate_matches_key?
    return false unless key
    return false unless certificate

    certificate.content.check_private_key(key.content)
  end

  # Generate all necessary parts of our ssl host.
  def generate
    generate_key unless key
    generate_certificate_request unless certificate_request

    # If we can get a CA instance, then we're a valid CA, and we
    # should use it to sign our request; else, just try to read
    # the cert.
    if ! certificate and ca = Puppet::SSL::CertificateAuthority.instance
      ca.sign(self.name)
    end
  end

  def initialize(name = nil)
    @name = (name || Puppet[:certname]).downcase
    @key = @certificate = @certificate_request = nil
    @ca = (name == self.class.ca_name)
  end

  # Extract the public key from the private key.
  def public_key
    key.content.public_key
  end

  # Create/return a store that uses our SSL info to validate
  # connections.
  def ssl_store(purpose = OpenSSL::X509::PURPOSE_ANY)
    unless @ssl_store
      @ssl_store = OpenSSL::X509::Store.new
      @ssl_store.purpose = purpose

      # Use the file path here, because we don't want to cause
      # a lookup in the middle of setting our ssl connection.
      @ssl_store.add_file(Puppet[:localcacert])

      # If there's a CRL, add it to our store.
      if crl = Puppet::SSL::CertificateRevocationList.indirection.find(CA_NAME)
        @ssl_store.flags = OpenSSL::X509::V_FLAG_CRL_CHECK_ALL|OpenSSL::X509::V_FLAG_CRL_CHECK if Puppet.settings[:certificate_revocation]
        @ssl_store.add_crl(crl.content)
      end
      return @ssl_store
    end
    @ssl_store
  end

  def state=(value)
    unless CERT_STATES.include?(value)
      string = CERT_STATES.join(", ")
      raise ArgumentError, "Invalid certificate state '#{value}'; must be one of #{string}"
    end
    @state = value
  end

  def to_pson(*args)
    pson_hash = {
      :name    => name,
      :message => '',
      :state   => 'invalid'
    }

    if certificate_request
      pson_hash[:fingerprint] = certificate_request.fingerprint
      pson_hash[:state] = 'requested'
    else
      if public_key = Puppet::SSL::Certificate.indirection.find(name)
       invalid = false
       begin
         certificate_authority = Puppet::SSL::CertificateAuthority.instance
         certificate_authority.verify(public_key)
       rescue Puppet::SSL::CertificateAuthority::CertificateVerificationError => details
         invalid = details.to_s
       end

       if invalid
         pson_hash[:state] = (invalid =~ /revoked/ ? 'revoked' : 'invalid')
         pson_hash[:verification_message] = invalid
         pson_hash[:fingerprint] = public_key.fingerprint
         pson_hash[:state] = 'signed'
       end
      else
        # Shouldn't have gotten here, since the host doesn't exist!
      end
    end

    pson_hash.to_pson(*args)
  end

  # Attempt to retrieve a cert, if we don't already have one.
  def wait_for_cert(time)
    begin
      return if certificate
      generate
      return if certificate
    rescue SystemExit,NoMemoryError
      raise
    rescue Exception => detail
      puts detail.backtrace if Puppet[:trace]
      Puppet.err "Could not request certificate: #{detail}"
      if time < 1
        puts "Exiting; failed to retrieve certificate and waitforcert is disabled"
        exit(1)
      else
        sleep(time)
      end
      retry
    end

    if time < 1
      puts "Exiting; no certificate found and waitforcert is disabled"
      exit(1)
    end

    while true
      sleep time
      begin
        break if certificate
        Puppet.notice "Did not receive certificate"
      rescue StandardError => detail
        puts detail.backtrace if Puppet[:trace]
        Puppet.err "Could not request certificate: #{detail}"
      end
    end
  end

end

require 'puppet/ssl/certificate_authority'
