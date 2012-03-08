Puppet::Type.newtype(:ini_setting) do
  # The only reasonable title 
  def self.title_patterns
    identity = lambda {|x| x}
    strip_brackets = lambda{|x| x.gsub(/^\[|\]$/, '')}

    [
      [/^(\S+)\s+\[([^\]]+)\]\s+([^=]+?)\s*=(.+)$/m,
        [[:file,    identity],
         [:section, strip_brackets],
         [:setting, identity],
         [:value,   identity]]],
      [/^(\S+)\s+\[([^\]]+)\]\s+(\S+)$/m,
        [[:file,    identity],
         [:section, strip_brackets],
         [:setting, identity]]],
      [/^\[([^\]]+)\]\s+(\S+)$/m,
        [[:section, strip_brackets],
         [:setting, identity]]],
      [/^(\S+)$/m,
        [[:setting, identity]]],
    ]
  end

  newparam(:file, :namevar => true) do
    validate do |value|
      unless Puppet::Util.absolute_path?(value)
        fail Puppet::Error, "File paths must be fully qualified, not '#{value}'"
      end
    end
  end

  newparam(:section, :namevar => true) do
  end

  newparam(:setting, :namevar => true) do
  end

  newproperty(:value) do
  end
end
