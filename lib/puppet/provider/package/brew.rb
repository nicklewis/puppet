require 'puppet/provider/package'
require 'uri'

Puppet::Type.type(:package).provide :brew, :parent => Puppet::Provider::Package do
    desc "Ruby Homebrew support."

    commands :brew => "brew"

    has_feature :versionable

    def install
        brew "install", resource[:name]
    end

    def uninstall
        brew "uninstall", resource[:name]
    end

    def update
        install
        cleanup
    end

    def cleanup
      brew "cleanup", resource[:name]
    end

    def query
        not self.class.cellar.find { |keg| keg[:name] == resource[:name] }.nil?
    end

    def self.instances
        cellar.collect do |keg|
            new(keg)
        end
    end

    def self.cellar
        command = [command(:brewcmd), "list"]
        output = execute(command)
        output.split.collect do |keg|
            { :name => keg, :ensure => :present, :provider => :brew }
        end
    end
end
