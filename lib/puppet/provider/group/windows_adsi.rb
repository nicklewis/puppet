
Puppet::Type.type(:group).provide :windows_adsi do
  desc "Group management for windows"

  defaultfor :operatingsystem => :windows
  confine :operatingsystem => :windows
  confine :true => Puppet.features.microsoft_windows?

  require 'puppet/util/windows_system'

  has_features :manages_members

  def group
    @group = Puppet::Util::Windows::Group.new(@resource[:name]) unless defined?(@group)
    @group
  end
  
  def members
    group.members
  end

  def members=(members)
    group.set_members(members)
  end

  def create
    @group = Puppet::Util::Windows::Group.create(@resource[:name])
    @group.set_members(@resource[:members])
  end

  def exists?
    Puppet::Util::Windows::Group.exists?(@resource[:name])
  end

  def delete
    Puppet::Util::Windows::Group.delete(@resource[:name])
  end

  def comment
    @resource[:comment]
  end

  def comment=(txt)
    @resource[:comment] = txt
  end

  def autogen_comment
    @resource[:name].capitalize
  end

  def gid
    nil
  end

  # returns collection of all groups
  def self.instances
    groups = Puppet::Util::Windows::Group.instances
    groups.collect{ |u| new( :name => u[ :name ] ) } unless groups.nil?
  end
end
