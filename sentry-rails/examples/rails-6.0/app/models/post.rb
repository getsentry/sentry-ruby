class Post < ApplicationRecord
  before_save do
    raise "foo"
  end
end
