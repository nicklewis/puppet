require 'puppet'
require 'puppet/indirector/certificate_status'
require 'puppet/ssl/certificate'
require 'puppet/ssl/certificate_authority'
require 'puppet/ssl/certificate_request'
require 'puppet/ssl/host'
require 'puppet/ssl/key'

class Puppet::Indirector::CertificateStatus::File < Puppet::Indirector::Code
  def ca
    raise ArgumentError, "This process is not configured as a certificate authority" unless Puppet::SSL::CertificateAuthority.ca?
    Puppet::SSL::CertificateAuthority.new
  end

  def destroy(request)
    [
      Puppet::SSL::Certificate,
      Puppet::SSL::CertificateRequest,
      Puppet::SSL::Key,
    ].collect do |part|
      part.indirection.destroy(request.key)
    end.any?
  end

  def save(request)
    name = request.key
    instance = request.instance

    if instance.certificate_request
      instance.certificate_request.class.indirection.save(instance.certificate_request)
    end

    ca.sign(request.key)
  end

  def search(request)

    # Support historic interface wherein users provide classes to filter
    # the search.  When used via the REST API, the arguments must be
    # a Symbol or an Array containing Symbol objects.
    klasses = case request.options[:for]
    when Class
      [request.options[:for]]
    when nil
      [
        Puppet::SSL::Certificate,
        Puppet::SSL::CertificateRequest,
        Puppet::SSL::Key,
      ]
    else
      [request.options[:for]].flatten.map do |klassname|
        indirection.class.model(klassname.to_sym)
      end
    end

    klasses.collect do |klass|
      klass.indirection.search(request.key, request.options)
    end.flatten.collect do |result|
      result.name
    end.uniq.collect &Puppet::SSL::Host.method(:new)
  end

  def find(request)

    result = Puppet::SSL::Host.new(request.key)
    if result.certificate_request || result.certificate
      result
    else
      nil
    end

  end
end
