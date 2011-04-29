require 'puppet/resource/catalog'
require 'puppet/indirector/rest'

class Puppet::Resource::Catalog::Rest < Puppet::Indirector::REST
  desc "Find resource catalogs over HTTP via REST."

  def fact_options(name)
  end

  def find(request)
    facts = Puppet::Node::Facts.indirection.find(request.key)
    format = facts.support_format?(:b64_zlib_yaml) ? :b64_zlib_yaml : :yaml
    text = facts.render(format)

    request.options.merge(:facts_format => format, :facts => CGI.escape(text))
    super
  end
end
