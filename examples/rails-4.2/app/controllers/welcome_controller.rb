class WelcomeController < ApplicationController
  def index
    Rails.logger.info("zomg division")
    1 / 0
  end
end
