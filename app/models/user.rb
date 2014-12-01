class User < ActiveRecord::Base
  devise :database_authenticatable, :registerable, :recoverable, :rememberable, :trackable, :validatable, :confirmable

  with_options if: :update? do |u|
    u.validates :name, presence: true
    u.validates :phone, presence: true
    u.validates :ic, presence: true, format: { with: /\A\d{6}-\d{2}-\d{4}\z/, message: "Invalid IC Format"   }, uniqueness: true
  end

  has_and_belongs_to_many :roles

  def has_role?(name)
    roles.include?(Role.find_by_name(name))
  end

  def update?
    if new_record?
      false
    else
      true
    end
  end

  def add_role(role)
    if  the_role = Role.find_by_name(role)
        roles.push(the_role)
    end
  end
  
  def delete_role(role)
    if  the_role = Role.find_by_name(role)
        roles.delete(the_role)
    end
  end
  
  def list_roles
    roles.map(&:name)
  end

end
