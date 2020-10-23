class Post < ApplicationRecord
  before_save :raise_error

  def raise_error
    raise "Post can't be saved!"
  end
end
