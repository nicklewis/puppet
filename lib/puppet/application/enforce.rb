require 'puppet/application'
require 'puppet/agent'
require 'puppet/configurer'
require 'puppet/ssl/oids'

class Puppet::Application::Enforce < Puppet::Application

  run_mode :agent

  def app_defaults
    super.merge({
      :catalog_terminus => :rest,
      :catalog_cache_terminus => :json,
      :node_terminus => :rest,
      :facts_terminus => :facter,
    })
  end

  def preinit
    # Do an initial trap, so that cancels don't get a stack trace.
    Signal.trap(:INT) do
      $stderr.puts "Cancelling startup"
      exit(0)
    end
  end

  option("--debug","-d")
  option("--verbose","-v")

  def help
    <<-'HELP'

puppet-enforce(8) -- The puppet configuration enforcer
========

SYNOPSIS
--------
Retrieves the client configuration from the puppet master and applies it to
the local host.
    HELP
  end

  def main
    begin
      transaction_uuid = SecureRandom.uuid
      report = Puppet::Transaction::Report.new('apply', nil, Puppet[:environment], transaction_uuid)
      agent = Puppet::Agent.new(Puppet::Configurer, false)
      agent.run(:report => report, :transaction_uuid => transaction_uuid)

      report.exit_status
    rescue => detail
      Puppet.log_exception(detail)
    end
  end

  def setup
    raise ArgumentError, "The puppet enforce command does not take parameters" unless command_line.args.empty?

    setup_logs

    Puppet::SSL::Oids.register_puppet_oids

    Puppet.settings.use :main, :agent, :ssl

    Puppet[:report] = true
    Puppet[:pluginsync] = true
    Puppet[:splay] = false

    Puppet::Transaction::Report.indirection.terminus_class = :rest
    # we want the last report to be persisted locally
    Puppet::Transaction::Report.indirection.cache_class = :yaml

    if Puppet[:noop]
      Puppet::Resource::Catalog.indirection.cache_class = nil
    elsif Puppet[:catalog_cache_terminus]
      Puppet::Resource::Catalog.indirection.cache_class = Puppet[:catalog_cache_terminus]
    end

    Puppet::SSL::Host.ca_location = :remote
  end

end
