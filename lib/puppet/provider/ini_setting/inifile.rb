require 'puppet/util/inifile'

Puppet::Type.type(:ini_setting).provide(:inifile) do
  def self.load_ini_file(filename)
    file = Puppet::Util::IniConfig::File.new
    file.read(filename) if File.exists?(filename)
    file
  end

  def self.cache(file)
    @files ||= {}
    @files[file] ||= load_ini_file(file)
  end

  def cache(file)
    self.class.cache(file)
  end

  def value
    file = cache(resource[:file])

    if section = file[resource[:section]]
      section[resource[:value]]
    else
      nil
    end
  end

  def value=(value)
    file = cache(resource[:file])
    section = file[resource[:section]] || file.add_section(resource[:section], resource[:file])
    section[resource[:setting]] = value
  end

  def flush
    cache(resource[:file]).store
  end
end
