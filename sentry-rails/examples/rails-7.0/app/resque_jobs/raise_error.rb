class RaiseError
  @queue = :default

  def self.perform
    1/0
  end
end
