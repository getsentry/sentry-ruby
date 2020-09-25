# typed: __STDLIB_INTERNAL

module Etc
  sig do
    returns(T::Hash[Symbol, String])
  end
  def self.uname; end
end
