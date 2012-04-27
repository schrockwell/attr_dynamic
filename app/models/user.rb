class User < ActiveRecord::Base
  
  attr_dynamic :name, :string
  attr_dynamic :height, :integer
  attr_dynamic :birthday, :datetime
  
  validates_presence_of :name
	
end