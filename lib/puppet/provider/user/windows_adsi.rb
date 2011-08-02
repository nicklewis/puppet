require 'puppet/provider'

Puppet::Type.type(:user).provide :windows_adsi do
  desc "User management for Windows"

  defaultfor :operatingsystem => :windows
  confine :operatingsystem => :windows
  confine :true => Puppet.features.microsoft_windows?

  require 'puppet/util/windows_system'

  has_features :manages_passwords

  def user
    @user = Puppet::Util::Windows::User.new(@resource[:name]) unless defined?(@user)
    @user
  end

  def password
    password = @resource[:password]
    user.password_is?(password) ?password :"" rescue :absent
  end

  def password=(pwd)
    user.password = @resource[:password]
  end

  def groups
    user.groups.join(',') rescue :absent
  end

  def groups=(groups)
    user.set_groups(groups, @resource[:membership] == :minimum)
  end

  def create
    @user = Puppet::Util::Windows::User.create(@resource[:name], @resource[:password])
    user.set_groups(@resource[:groups], @resource[:membership] == :minimum)
  end

  def exists?
    return Puppet::Util::Windows::User.exists?(@resource[:name])
  end

  def delete
    Puppet::Util::Windows::User.delete(@resource[:name])
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

  def home
    nil
  end
  
  def uid
    nil
  end
 
  def gid
    nil
  end

  def shell
    nil
  end

  # returns collection of all users
  def self.instances
    users = Puppet::Util::Windows::User.instances
    users.collect{ |u| new( :name => u[ :name ] ) } unless users.nil?
    #[]
    #users ||= []
    #wmi = WIN32OLE.connect( Puppet::Util::Windows::Computer.wmi_resource_uri )
    #wql = wmi.execquery( "select * from win32_useraccount" )
    #wql.each{ |u| users << new( :name => u.name ) } unless wql.nil?
    # users
  end
end
