require 'puppet/provider/package'
require 'uri'

# Ruby gems support.
Puppet::Type.type(:package).provide :gem, :parent => Puppet::Provider::Package do
  desc "Ruby Gem support.  If a URL is passed via `source`, then that URL is used as the
    remote gem repository; if a source is present but is not a valid URL, it will be
    interpreted as the path to a local gem file.  If source is not present at all,
    the gem will be installed from the default gem repositories."

  has_feature :versionable

  commands :gem => "gem"

  def self.gemlist(hash)
    args = ['list']

    args << hash[:local] ? '--local' : '--remote'

    args << name + "$" if name = hash[:justme]

    begin
      list = gem(*args).lines.map do |set|
        gemsplit(set)
      end.compact
    rescue Puppet::ExecutionFailure => detail
      raise Puppet::Error, "Could not list gems: #{detail}"
    end

    hash[:justme] ? list.first : list
  end

  def self.gemsplit(desc)
    case desc
    when /^\*\*\*/, /^\s*$/, /^\s+/; return nil
    when /^(\S+)\s+\((.+)\)/
      name = $1
      version = $2.split(/,\s*/)[0]
      {
        :name => name,
        :ensure => version,
        :provider => :gem,
      }
    else
      Puppet.warning "Could not match #{desc}"
      nil
    end
  end

  def self.instances
    gemlist(:local => true).collect do |hash|
      new(hash)
    end
  end

  def install(useversion = true)
    args = []
    args << "-v" << resource[:ensure] if (! resource[:ensure].is_a? Symbol) and useversion

    if source = resource[:source]
      begin
        uri = URI.parse(source)
      rescue => detail
        fail "Invalid source '#{uri}': #{detail}"
      end

      case uri.scheme
      when nil
        # no URI scheme => interpret the source as a local file
        args << source
      when /file/i
        args << uri.path
      when 'puppet'
        # we don't support puppet:// URLs (yet)
        raise Puppet::Error.new("puppet:// URLs are not supported as gem sources")
      else
        # interpret it as a gem repository
        args.concat ['--source', source, resource[:name]]
      end
    else
      args.concat ['--no-rdoc', '--no-ri', resource[:name]]
    end

    # Always include dependencies
    output = gem('install', '--include-dependencies', *args)

    # Apparently some stupid gem versions don't exit non-0 on failure
    self.fail "Could not install: #{output.chomp}" if output.include?("ERROR")
  end

  def latest
    # This always gets the latest version available.
    hash = self.class.gemlist(:justme => resource[:name])

    hash[:ensure]
  end

  def query
    self.class.gemlist(:justme => resource[:name], :local => true)
  end

  def uninstall
    gem *%W[uninstall -x -a #{resource[:name]}]
  end

  def update
    self.install(false)
  end
end
