class ErrorDelayedJob
  def self.perform
    1/0
  end
end
