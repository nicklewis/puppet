# Manage indirections to termini.  They are organized in terms of indirections -
# - e.g., configuration, node, file, certificate -- and each indirection has one
# or more terminus types defined.  The indirection is configured via the
# +indirects+ method, which will be called by the class extending itself
# with this module.
module Puppet::Indirector
  # LAK:FIXME We need to figure out how to handle documentation for the
  # different indirection types.

  require 'puppet/indirector/indirection'
  require 'puppet/indirector/terminus'
  require 'puppet/indirector/envelope'
  require 'puppet/network/format_handler'

  def self.configure_routes(application_routes)
    application_routes.each do |indirection_name, terminuses|
      indirection_name = indirection_name.to_sym

      indirection = Puppet::Indirector::Indirection.instance(indirection_name)
      raise "Indirection #{indirection_name} does not exist" unless indirection

      # Load the terminus classes
      Puppet::Indirector::Terminus.terminus_classes(indirection_name)

      terminuses.each do |method, method_terminuses|
        method_terminuses = method_terminuses.split(',').map(&:strip) if method_terminuses.is_a? String
        indirection.terminuses[method.to_sym] = method_terminuses.map{|t| indirection.make_terminus(t)}
      end
    end
  end

  # Declare that the including class indirects its methods to
  # this terminus.  The terminus name must be the name of a Puppet
  # default, not the value -- if it's the value, then it gets
  # evaluated at parse time, which is before the user has had a chance
  # to override it.
  def indirects(indirection, options = {})
    raise(ArgumentError, "Already handling indirection for #{@indirection.name}; cannot also handle #{indirection}") if @indirection
    # populate this class with the various new methods
    extend ClassMethods
    include Puppet::Indirector::Envelope
    extend Puppet::Network::FormatHandler

    # instantiate the actual Terminus for that type and this name (:ldap, w/ args :node)
    # & hook the instantiated Terminus into this class (Node: @indirection = terminus)
    @indirection = Puppet::Indirector::Indirection.new(self, indirection,  options)
  end

  module ClassMethods
    attr_reader :indirection
  end
end
