class AppearanceChannel < ApplicationCable::Channel
  def subscribed
  end

  def unsubscribed
  end

  def hello
  end

  def goodbye(data)
    1 / 0
  end
end
