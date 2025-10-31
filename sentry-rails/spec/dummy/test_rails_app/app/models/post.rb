# frozen_string_literal: true

class Post < ActiveRecord::Base
  has_many :comments
  has_one_attached :cover
end
