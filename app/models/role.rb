# -*- encoding : utf-8 -*-
class Role < ActiveRecord::Base
  has_many :role_rights, :dependent => :delete_all;
end
